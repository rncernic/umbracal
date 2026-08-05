unit USun;

{ Internal solar calculation engine.
  VSOP87 series, nutation, and iterative rise/set solving.
  Not intended to be used directly — call TSunEngine from UUmbracal instead.

  Time scales: Refresh() takes a UT Julian Date. Everything ephemeris-related
  runs on TT (JD_UT + DeltaT); sidereal time runs on UT. Mixing the two was
  the previous behaviour and is worth about a minute of arc in longitude. }

{$mode ObjFPC}{$H+}

interface

uses
  Math, SysUtils,
  UAngle,    // TObserver, TAngle, TTwilight, TRiseSet, THorizontal, ...
  UHelper,   // NormalizeHours, Normalize360, Normalize2Pi, RefractAltitude, HorizonDip
  UTime,     // TTimeScales, sidereal time, equation of time
  UVSOP87,   // VSOP87 coefficient tables
  UEarth;    // Nutation

const
  CSunriseAltitude      = -0.8333;   // refracted upper limb
  CCivilTwilight        = -6.0;
  CNauticalTwilight     = -12.0;
  CAstronomicalTwilight = -18.0;

  CSemiDiameterAt1AU    = 0.2666;    // degrees
  CVSOPScale            = 1e-8;

  { Return codes from HourAngleForAltitude }
  CEventNormal     = 0;
  CEventPolarDay   = 1;
  CEventPolarNight = 2;

type
  { Snapshot of the instant's ephemeris, so the rise/set solver can scribble
    over the working fields and put them back afterwards. }
  TSunState = record
    Geocentric:         TGeocentric;
    ApparentLongitude:  Double;
    ApparentEquatorial: TEquatorial;
  end;

  TSun = class
  private
    FDeltaPsiDeg: Double;
    FDeltaEpsDeg: Double;
    FEps0Deg:     Double;

    { ——— VSOP87 ——— }
    function  CalcVSOPSum(const ATerms: array of TVector3; AU: Double): Double;

    { ——— Step calculations ——— }
    procedure UpdateNutation(AJC_TT: Double);
    procedure UpdateGeocentricPosition(AU: Double);
    procedure UpdateApparentLongitude;
    procedure UpdateApparentCoordinates;
    procedure UpdateSolarState(AJC_TT: Double);
    procedure UpdateHorizontalPosition;

    { ——— Rise / set solvers ——— }
    function  EventAltitude(AAltitudeDeg: Double): Double;
    function  HourAngleForAltitude(AAltitudeDeg: Double;
                out AHourAngleDeg: Double): Integer;
    function  SolarNoonUT(AJC_TT: Double): Double;
    function  SolveAltitude(AAltitudeDeg: Double): TTwilight;
    function  RefineEvent(AGuessHour, AAltitudeDeg: Double;
                AIsRise: Boolean): Double;
    function  SolveAltitudeIterative(AAltitudeDeg: Double): TTwilight;

    { ——— State management ——— }
    function  SaveState: TSunState;
    procedure RestoreState(const AState: TSunState);

  public
    Observer:           TObserver;
    Time:               TTimeScales;

    { Ephemeris at the requested instant }
    Geocentric:         TGeocentric;
    ApparentLongitude:  Double;       // radians
    ApparentEquatorial: TEquatorial;
    ApparentAltAz:      THorizontal;
    SemiDiameterDeg:    Double;

    { Nutation / obliquity, degrees }
    DeltaPsiDeg:        Double;
    TrueObliquityDeg:   Double;

    { Time-derived quantities }
    EoTMinutes:         Double;
    GMSTDeg:            Double;   // Greenwich mean sidereal
    GASTDeg:            Double;   // Greenwich apparent sidereal
    LSTDeg:             Double;   // Local apparent sidereal
    GHASunDeg:          Double;   // Greenwich hour angle of the Sun, 0..360 W
    LHASunDeg:          Double;   // Local hour angle,               0..360 W
    HourAngleDeg:       Double;   // Same, folded to (-180, 180] for dial math

    RiseSet:            TRiseSet;

    constructor Create(const AObserver: TObserver);

    { Run everything for the given UT Julian Date. Pass ADeltaTOverride >= 0
      to supply a measured value instead of the polynomial. }
    procedure Refresh(const AJD_UT: Double;
      const ADeltaTOverride: Double = -1.0);
  end;

implementation

{ ============================================================
  Constructor
  ============================================================ }

constructor TSun.Create(const AObserver: TObserver);
begin
  Observer := AObserver;
end;

{ ============================================================
  State snapshot
  ============================================================ }

function TSun.SaveState: TSunState;
begin
  Result.Geocentric         := Geocentric;
  Result.ApparentLongitude  := ApparentLongitude;
  Result.ApparentEquatorial := ApparentEquatorial;
end;

procedure TSun.RestoreState(const AState: TSunState);
begin
  Geocentric         := AState.Geocentric;
  ApparentLongitude  := AState.ApparentLongitude;
  ApparentEquatorial := AState.ApparentEquatorial;
end;

{ ============================================================
  VSOP87 helpers
  ============================================================ }

function TSun.CalcVSOPSum(const ATerms: array of TVector3; AU: Double): Double;
var
  LIdx: Integer;
begin
  Result := 0;
  for LIdx := Low(ATerms) to High(ATerms) do
    Result := Result + ATerms[LIdx][0] * Cos(ATerms[LIdx][1] + ATerms[LIdx][2] * AU);
end;

{ ============================================================
  Step 0 — Nutation and obliquity
  ============================================================ }

procedure TSun.UpdateNutation(AJC_TT: Double);
begin
  { UEarth.Nutation returns dPsi and dEps in DEGREES (0.0001" / 1e4 / 3600),
    and eps0 in degrees. }
  Nutation(AJC_TT, FDeltaPsiDeg, FDeltaEpsDeg, FEps0Deg);

  DeltaPsiDeg      := FDeltaPsiDeg;
  TrueObliquityDeg := FEps0Deg + FDeltaEpsDeg;
end;

{ ============================================================
  Step 1 — Geocentric ecliptic position via VSOP87
  ============================================================ }

procedure TSun.UpdateGeocentricPosition(AU: Double);
var
  LLSum: array[0..5] of Double;
  LBSum: array[0..4] of Double;
  LRSum: array[0..5] of Double;
  LL, LB, LR: Double;
  LT, LLambdaPrime, LDeltaTheta, LDeltaBeta: Double;
begin
  { Heliocentric longitude (L) — Earth }
  LLSum[0] := CalcVSOPSum(VSOP87EarthL0, AU);
  LLSum[1] := CalcVSOPSum(VSOP87EarthL1, AU);
  LLSum[2] := CalcVSOPSum(VSOP87EarthL2, AU);
  LLSum[3] := CalcVSOPSum(VSOP87EarthL3, AU);
  LLSum[4] := CalcVSOPSum(VSOP87EarthL4, AU);
  LLSum[5] := CalcVSOPSum(VSOP87EarthL5, AU);

  LL := (((((LLSum[5]*AU + LLSum[4])*AU + LLSum[3])*AU
           + LLSum[2])*AU + LLSum[1])*AU + LLSum[0]) * CVSOPScale;
  LL := Normalize2Pi(LL + Pi);  // convert Earth -> Sun, geocentric

  { Heliocentric latitude (B) }
  LBSum[0] := CalcVSOPSum(VSOP87EarthB0, AU);
  LBSum[1] := CalcVSOPSum(VSOP87EarthB1, AU);
  LBSum[2] := CalcVSOPSum(VSOP87EarthB2, AU);
  LBSum[3] := CalcVSOPSum(VSOP87EarthB3, AU);
  LBSum[4] := CalcVSOPSum(VSOP87EarthB4, AU);
  LB := ((((LBSum[4]*AU + LBSum[3])*AU + LBSum[2])*AU
           + LBSum[1])*AU + LBSum[0]) * CVSOPScale;
  LB := -LB;

  { Radius vector (R) in AU }
  LRSum[0] := CalcVSOPSum(VSOP87EarthR0, AU);
  LRSum[1] := CalcVSOPSum(VSOP87EarthR1, AU);
  LRSum[2] := CalcVSOPSum(VSOP87EarthR2, AU);
  LRSum[3] := CalcVSOPSum(VSOP87EarthR3, AU);
  LRSum[4] := CalcVSOPSum(VSOP87EarthR4, AU);
  LRSum[5] := CalcVSOPSum(VSOP87EarthR5, AU);
  LR := (((((LRSum[5]*AU + LRSum[4])*AU + LRSum[3])*AU
            + LRSum[2])*AU + LRSum[1])*AU + LRSum[0]) * CVSOPScale;

  { FK5 frame correction — Meeus §32 }
  LT            := AU * 10;  // Julian centuries
  LLambdaPrime  := LL - 1.397 * DEG_TO_RAD * LT - 0.00031 * DEG_TO_RAD * LT * LT;
  LDeltaTheta   := -(0.09033 / 3600.0) * DEG_TO_RAD;
  LDeltaBeta    := (0.03916 / 3600.0) * DEG_TO_RAD
                   * (Cos(LLambdaPrime) - Sin(LLambdaPrime));

  Geocentric.Longitude    := LL + LDeltaTheta;
  Geocentric.Latitude     := LB - LDeltaBeta;
  Geocentric.RadiusVector := LR;
end;

{ ============================================================
  Step 2 — Apparent longitude (nutation + aberration)
  ============================================================ }

procedure TSun.UpdateApparentLongitude;
var
  LAberration: Double;
begin
  if Geocentric.RadiusVector <> 0 then
    LAberration := -(20.4898 / 3600.0) * DEG_TO_RAD / Geocentric.RadiusVector
  else
    LAberration := 0;

  ApparentLongitude := Geocentric.Longitude
                       + FDeltaPsiDeg * DEG_TO_RAD
                       + LAberration;
end;

{ ============================================================
  Step 3 — Apparent RA / Dec
  ============================================================ }

procedure TSun.UpdateApparentCoordinates;
var
  LEpsilon: Double;
  LEpsSin, LEpsCos: Double;
  LGLatSin, LGLatCos: Double;
  LAppLonSin, LAppLonCos: Double;
  LRA, LDec: Double;
begin
  { True obliquity from UEarth.Nutation — no second series needed. }
  LEpsilon := TrueObliquityDeg * DEG_TO_RAD;

  Math.SinCos(LEpsilon,            LEpsSin,    LEpsCos);
  Math.SinCos(Geocentric.Latitude, LGLatSin,   LGLatCos);
  Math.SinCos(ApparentLongitude,   LAppLonSin, LAppLonCos);

  { Meeus Eq. 13.4 — Declination }
  LDec := ArcSin(LGLatSin * LEpsCos + LGLatCos * LEpsSin * LAppLonSin);

  { Meeus Eq. 13.3 — Right Ascension }
  LRA := ArcTan2(LEpsCos * LAppLonSin - Tan(Geocentric.Latitude) * LEpsSin,
                 LAppLonCos);
  LRA := Normalize2Pi(LRA);

  ApparentEquatorial.RightAscensionRad := LRA;
  ApparentEquatorial.DeclinationRad    := LDec;
  ApparentEquatorial.RightAscensionDeg := LRA * RAD_TO_DEG;
  ApparentEquatorial.DeclinationDeg    := LDec * RAD_TO_DEG;
end;

{ Full ephemeris chain for one TT epoch. }
procedure TSun.UpdateSolarState(AJC_TT: Double);
begin
  UpdateNutation(AJC_TT);
  UpdateGeocentricPosition(AJC_TT / 10.0);   // Julian millennia
  UpdateApparentLongitude;
  UpdateApparentCoordinates;
end;

{ ============================================================
  Step 4 — Topocentric altitude / azimuth
  ============================================================ }

procedure TSun.UpdateHorizontalPosition;
var
  LLat, LHA: Double;
  LDecSin, LDecCos, LLatSin, LLatCos, LHASin, LHACos: Double;
  LAlt, LAz: Double;
begin
  GMSTDeg := GreenwichMeanSiderealDeg(Time.JD_UT);
  GASTDeg := GreenwichApparentSiderealDeg(Time.JD_UT, DeltaPsiDeg,
                                          TrueObliquityDeg);
  LSTDeg  := LocalSiderealDeg(GASTDeg, Observer.Longitude.Degrees);

  GHASunDeg    := Normalize360(GASTDeg - ApparentEquatorial.RightAscensionDeg);
  LHASunDeg    := Normalize360(GHASunDeg + Observer.Longitude.Degrees);
  HourAngleDeg := Normalize180(LHASunDeg);

  LHA  := HourAngleDeg * DEG_TO_RAD;
  LLat := Observer.Latitude.Degrees * DEG_TO_RAD;

  Math.SinCos(ApparentEquatorial.DeclinationRad, LDecSin, LDecCos);
  Math.SinCos(LLat, LLatSin, LLatCos);
  Math.SinCos(LHA,  LHASin,  LHACos);

  LAlt := ArcSin(LLatSin * LDecSin + LLatCos * LDecCos * LHACos);

  { Azimuth — this expression yields the navigational (N=0) value directly;
    verified against both hemispheres at transit. }
  LAz := ArcTan2(-LHASin,
                 Tan(ApparentEquatorial.DeclinationRad) * LLatCos - LLatSin * LHACos);
  if LAz < 0 then LAz := LAz + TWO_PI;

  ApparentAltAz.AzimuthNav   := LAz * RAD_TO_DEG;
  ApparentAltAz.AzimuthAstro := Normalize360(LAz * RAD_TO_DEG + 180.0);

  { Refracted altitude. Horizon dip is NOT applied here — it belongs to the
    rise/set threshold (see EventAltitude), not to the position readout. }
  ApparentAltAz.Altitude := RefractAltitude(LAlt * RAD_TO_DEG);

  if Geocentric.RadiusVector <> 0 then
    SemiDiameterDeg := CSemiDiameterAt1AU / Geocentric.RadiusVector
  else
    SemiDiameterDeg := CSemiDiameterAt1AU;
end;

{ ============================================================
  Rise / set
  ============================================================ }

{ Elevation lowers the visible horizon, so an observer on a hill sees the sun
  rise earlier. HorizonDip returns a negative value, so adding it lowers the
  threshold — which is the intended direction. }
function TSun.EventAltitude(AAltitudeDeg: Double): Double;
begin
  Result := AAltitudeDeg + HorizonDip(Observer.Elevation);
end;

function TSun.HourAngleForAltitude(AAltitudeDeg: Double;
  out AHourAngleDeg: Double): Integer;
var
  LLat, LDec, LCosH, LDen: Double;
begin
  AHourAngleDeg := 0;
  LLat := Observer.Latitude.Degrees * DEG_TO_RAD;
  LDec := ApparentEquatorial.DeclinationRad;

  LDen := Cos(LLat) * Cos(LDec);
  if Abs(LDen) < 1e-12 then Exit(CEventPolarNight);

  LCosH := (Sin(EventAltitude(AAltitudeDeg) * DEG_TO_RAD)
            - Sin(LLat) * Sin(LDec)) / LDen;

  if LCosH >  1.0 then Exit(CEventPolarNight);
  if LCosH < -1.0 then Exit(CEventPolarDay);

  AHourAngleDeg := ArcCos(LCosH) * RAD_TO_DEG;
  Result := CEventNormal;
end;

function TSun.SolarNoonUT(AJC_TT: Double): Double;
begin
  Result := 12.0
            - Observer.Longitude.Degrees / 15.0
            - EquationOfTimeMinutes(AJC_TT) / 60.0;
end;

function TSun.SolveAltitude(AAltitudeDeg: Double): TTwilight;
var
  LH, LNoon: Double;
begin
  FillChar(Result, SizeOf(Result), 0);

  case HourAngleForAltitude(AAltitudeDeg, LH) of
    CEventPolarNight: begin Result.TwilightType := 'PolarNight'; Exit; end;
    CEventPolarDay:   begin Result.TwilightType := 'PolarDay';   Exit; end;
  end;

  LNoon := SolarNoonUT(Time.JC_TT);

  Result.Rise         := NormalizeHours(LNoon - LH / 15.0);
  Result.SetTime      := NormalizeHours(LNoon + LH / 15.0);
  Result.Culmination  := NormalizeHours(LNoon);
  Result.TwilightType := 'Normal';
end;

{ Re-solve the event using the sun's position AT the event, not at the
  requested instant. Each pass recomputes the ephemeris for the current guess
  and converges in two or three iterations. }
function TSun.RefineEvent(AGuessHour, AAltitudeDeg: Double;
  AIsRise: Boolean): Double;
var
  LT, LPrev, LJD, LJC, LH, LNoon: Double;
  LIter: Integer;
begin
  LT := AGuessHour;

  for LIter := 0 to 3 do
  begin
    LPrev := LT;

    { TT centuries at the guessed instant on this UT day. }
    LJD := Time.DayStart + LT / 24.0;
    LJC := (LJD + Time.DeltaTSec / 86400.0 - J2000) / 36525.0;

    UpdateSolarState(LJC);

    if HourAngleForAltitude(AAltitudeDeg, LH) <> CEventNormal then Break;

    LNoon := SolarNoonUT(LJC);
    if AIsRise then
      LT := LNoon - LH / 15.0
    else
      LT := LNoon + LH / 15.0;

    if Abs(LT - LPrev) < 1.0 / 3600.0 then Break;   // one second
  end;

  Result := NormalizeHours(LT);
end;

function TSun.SolveAltitudeIterative(AAltitudeDeg: Double): TTwilight;
begin
  Result := SolveAltitude(AAltitudeDeg);
  if Result.TwilightType <> 'Normal' then Exit;

  Result.Rise        := RefineEvent(Result.Rise,    AAltitudeDeg, True);
  Result.SetTime     := RefineEvent(Result.SetTime, AAltitudeDeg, False);
  Result.Culmination := NormalizeHours(SolarNoonUT(Time.JC_TT));
end;

{ ============================================================
  Public interface
  ============================================================ }

procedure TSun.Refresh(const AJD_UT: Double; const ADeltaTOverride: Double);
var
  LState: TSunState;
begin
  Time := BuildTimeScales(AJD_UT, ADeltaTOverride);

  { Ephemeris for the requested instant, on TT. }
  UpdateSolarState(Time.JC_TT);
  UpdateHorizontalPosition;

  EoTMinutes := EquationOfTimeMinutes(Time.JC_TT);

  { The rise/set solver walks the ephemeris to other epochs, so snapshot the
    instant's values and put them back when it is done. }
  LState := SaveState;
  try
    RiseSet.Sunrise      := SolveAltitudeIterative(CSunriseAltitude);
    RiseSet.Civil        := SolveAltitudeIterative(CCivilTwilight);
    RiseSet.Nautical     := SolveAltitudeIterative(CNauticalTwilight);
    RiseSet.Astronomical := SolveAltitudeIterative(CAstronomicalTwilight);
  finally
    RestoreState(LState);
  end;
end;

end.
