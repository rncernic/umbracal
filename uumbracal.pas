unit UUmbracal;

{ Public façade over the solar engine.

  Everything is computed ONCE in the constructor and cached in a single
  TDialResult. The previous version rebuilt a TSun (full VSOP87 plus four
  iterative rise/set solves) on every property read, so a form update that
  touched four properties ran the engine four times.

  Only mainform depends on this unit. }

{$mode ObjFPC}{$H+}
{$MODESWITCH ADVANCEDRECORDS}

interface

uses
  Classes, SysUtils, Math,
  UAngle,
  UHelper,
  UTime,
  UHours;

type
  { TDialResult — every quantity the UI displays, for one instant. }
  TDialResult = record
    { ——— Time scales ——— }
    JD_UT:            Double;
    JD_TT:            Double;
    DeltaTSec:        Double;
    UTHours:          Double;   // [0, 24)
    LocalHours:       Double;   // civil / zone time
    LMTHours:         Double;   // local mean time
    SundialHours:     Double;   // local apparent time — what the dial reads
    DayOfWeek:        Integer;  // 0 = Sunday

    { ——— Dialist corrections, minutes ——— }
    EoTMinutes:       Double;
    LongitudeCorrMin: Double;
    TotalCorrMin:     Double;   // sundial time minus zone clock time

    { ——— Sidereal, degrees and hours ——— }
    GMSTDeg:          Double;
    GASTDeg:          Double;
    LSTDeg:           Double;
    LSTHours:         Double;

    { ——— Ephemeris ——— }
    Equatorial:       TEquatorial;
    Horizontal:       THorizontal;
    SunLongitudeDeg:  Double;   // apparent geocentric ecliptic longitude
    RadiusVectorAU:   Double;
    SemiDiameterDeg:  Double;
    GHAVernalDeg:     Double;
    GHASunDeg:        Double;
    LHASunDeg:        Double;
    HourAngleDeg:     Double;   // (-180, 180], negative before noon

    { ——— Events and ancient hours ——— }
    RiseSet:          TRiseSet;
    Hours:            THourSystems;

    { ——— Dial geometry ——— }
    SunUp:            Boolean;
    ShadowRatio:      Double;   // shadow length / gnomon height, sun up only
    ShadowAzimuthDeg: Double;   // direction the shadow points, N = 0
    ShadowSpeedDegHr: Double;   // hour-line angular velocity, horizontal dial
  end;

  { TSunEngine — construct, then read Data. }
  TSunEngine = class
  private
    FObserver         : TObserver;
    FZoneHours        : Double;
    FData             : TDialResult;
    FStandardZoneHours: Double;
    procedure Compute(const AJD_UT, ADeltaTOverride: Double);
  public
    { AZoneHours is the offset applied to UT to get civil time, DST included.
      ADeltaTOverride < 0 selects the built-in polynomial. }
    constructor Create(const AObserver: TObserver; const AJD_UT: Double;
      const AZoneHours: Double = 0.0;
      const AStandardZoneHours: Double = -999.0;
      const ADeltaTOverride: Double = -1.0);

    function RiseSet: TRiseSet;
    function SunPosition: THorizontal;

    property Data: TDialResult read FData;
    property Observer: TObserver read FObserver;
    property ZoneHours: Double read FZoneHours;
  end;

{ Angular velocity of the shadow of a polar style on a HORIZONTAL dial, in
  degrees per hour. Independent of declination: on a horizontal dial the hour
  line satisfies tan(theta) = sin(lat) * tan(H), so d(theta)/dH = sin(lat) /
  (cos^2 H + sin^2 lat * sin^2 H). An equatorial dial would give a flat 15. }
function ShadowSpeedHorizontal(const ALatitudeDeg, AHourAngleDeg: Double): Double;

implementation

uses
  USun;   // internal engine — not exposed to callers

function ShadowSpeedHorizontal(const ALatitudeDeg, AHourAngleDeg: Double): Double;
var
  LLatSin, LHSin, LHCos, LDen: Double;
begin
  LLatSin := Sin(ALatitudeDeg * DEG_TO_RAD);
  LHSin   := Sin(AHourAngleDeg * DEG_TO_RAD);
  LHCos   := Cos(AHourAngleDeg * DEG_TO_RAD);

  LDen := LHCos * LHCos + LLatSin * LLatSin * LHSin * LHSin;
  if LDen < 1e-12 then Exit(0.0);

  Result := Abs(15.0 * LLatSin / LDen);
end;

constructor TSunEngine.Create(const AObserver: TObserver; const AJD_UT: Double;
      const AZoneHours: Double; const AStandardZoneHours: Double;
      const ADeltaTOverride: Double);
begin
  inherited Create;
  FObserver  := AObserver;
  if AStandardZoneHours <= -100.0 then
    FStandardZoneHours := AZoneHours
  else
    FStandardZoneHours := AStandardZoneHours;
  Compute(AJD_UT, ADeltaTOverride);
end;

procedure TSunEngine.Compute(const AJD_UT, ADeltaTOverride: Double);
var
  LSun: TSun;
  LAltRad: Double;
begin
  FillChar(FData, SizeOf(FData), 0);

  LSun := TSun.Create(FObserver);
  try
    LSun.Refresh(AJD_UT, ADeltaTOverride);

    { ——— Time scales ——— }
    FData.JD_UT     := LSun.Time.JD_UT;
    FData.JD_TT     := LSun.Time.JD_TT;
    FData.DeltaTSec := LSun.Time.DeltaTSec;
    FData.UTHours   := LSun.Time.UTHours;
    FData.DayOfWeek := DayOfWeekFromJD(AJD_UT);

    FData.LocalHours := NormalizeHours(FData.UTHours + FZoneHours);
    FData.LMTHours   := NormalizeHours(FData.UTHours
                        + FObserver.Longitude.Degrees / 15.0);

    { ——— Corrections ——— }
    FData.EoTMinutes       := LSun.EoTMinutes;
    FData.LongitudeCorrMin := LongitudeCorrectionMinutes(
                                FObserver.Longitude.Degrees, FStandardZoneHours);
    FData.TotalCorrMin     := FData.LongitudeCorrMin + FData.EoTMinutes;

    { Local apparent time = local mean time + equation of time. }
    FData.SundialHours := NormalizeHours(FData.LMTHours
                          + FData.EoTMinutes / 60.0);

    { ——— Sidereal ——— }
    FData.GMSTDeg   := LSun.GMSTDeg;
    FData.GASTDeg   := LSun.GASTDeg;
    FData.LSTDeg    := LSun.LSTDeg;
    FData.LSTHours  := LSun.LSTDeg / 15.0;

    { ——— Ephemeris ——— }
    FData.Equatorial      := LSun.ApparentEquatorial;
    FData.Horizontal      := LSun.ApparentAltAz;
    FData.SunLongitudeDeg := Normalize360(LSun.ApparentLongitude * RAD_TO_DEG);
    FData.RadiusVectorAU  := LSun.Geocentric.RadiusVector;
    FData.SemiDiameterDeg := LSun.SemiDiameterDeg;
    FData.GHAVernalDeg    := LSun.GASTDeg;
    FData.GHASunDeg       := LSun.GHASunDeg;
    FData.LHASunDeg       := LSun.LHASunDeg;
    FData.HourAngleDeg    := LSun.HourAngleDeg;

    { ——— Events ——— }
    FData.RiseSet := LSun.RiseSet;

    { ——— Ancient hour systems ——— }
    FData.Hours := ComputeHourSystems(
                     FData.UTHours,
                     FData.RiseSet.Sunrise.Rise,
                     FData.RiseSet.Sunrise.SetTime,
                     FData.RiseSet.Sunrise.TwilightType = 'Normal');

    { ——— Dial geometry ——— }
    FData.SunUp := FData.Horizontal.Altitude > 0.0;
    if FData.SunUp then
    begin
      LAltRad := FData.Horizontal.Altitude * DEG_TO_RAD;
      FData.ShadowRatio := 1.0 / Tan(LAltRad);
    end
    else
      FData.ShadowRatio := 0.0;

    FData.ShadowAzimuthDeg := Normalize360(FData.Horizontal.AzimuthNav + 180.0);
    FData.ShadowSpeedDegHr := ShadowSpeedHorizontal(
                                FObserver.Latitude.Degrees,
                                FData.HourAngleDeg);
  finally
    LSun.Free;
  end;
end;

function TSunEngine.RiseSet: TRiseSet;
begin
  Result := FData.RiseSet;
end;

function TSunEngine.SunPosition: THorizontal;
begin
  Result := FData.Horizontal;
end;

end.
