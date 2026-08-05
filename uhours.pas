unit UHours;

{ Ancient hour reckonings used in gnomonics: temporal (unequal / planetary),
  Babylonian and Italian hours.

  All three are differences between an instant and a rise/set event, so they
  are independent of the time scale used: feed UT, LMT or local apparent time,
  provided every argument shares the same scale. Nothing here needs the
  equation of time or the longitude correction.

  Companion to a_angle / a_helper. }

{$mode ObjFPC}{$H+}
{$MODESWITCH ADVANCEDRECORDS}

interface

uses
  Classes, SysUtils, Math,
  UHelper;

type
  { THourSystems — the three reckonings evaluated at one instant }
  THourSystems = record
    Valid:           Boolean;  // False on polar day / polar night
    IsDaytime:       Boolean;  // sun above the rise/set threshold

    Temporal:        Double;   // 0 at sunrise .. 12 at sunset (daytime)
    Nocturnal:       Double;   // 0 at sunset  .. 12 at sunrise (night)
    Babylonian:      Double;   // equal hours elapsed since sunrise, 0..24
    Italian:         Double;   // equal hours, 24 at sunset, 0..24

    DayLength:       Double;   // decimal hours
    NightLength:     Double;   // decimal hours
    TemporalLength:  Double;   // length of one diurnal temporal hour
    NocturnalLength: Double;   // length of one nocturnal temporal hour
    UntilSunset:     Double;   // hours remaining to the next sunset
    SinceSunrise:    Double;   // hours elapsed since the last sunrise

    { Ordinal forms: the hour currently *running*, as engraved on a dial. }
    function TemporalOrdinal:   Integer;  // 1..12
    function BabylonianOrdinal: Integer;  // 1..24
    function ItalianOrdinal:    Integer;  // 1..24
  end;

{ Core entry point. ANow, ASunrise and ASunset are decimal hours in any single
  consistent scale; day-wrap is handled internally. Set AHasRiseSet to False
  for polar day / polar night. }
function ComputeHourSystems(const ANow, ASunrise, ASunset: Double;
  const AHasRiseSet: Boolean = True): THourSystems;

{ Semi-diurnal arc H0, in degrees, for drawing hour lines across a range of
  declinations. AHorizonAlt is the altitude defining the event: 0 for the
  geometric horizon (the classical dialling convention), -0.8333 for the
  refracted upper limb. Returns False when the sun does not rise or set. }
function SemiDiurnalArc(const ALatitudeDeg, ADeclinationDeg: Double;
  out AH0Deg: Double; const AHorizonAlt: Double = 0.0): Boolean;

{ Analytic form, parametrised by hour angle rather than by clock time. Useful
  when generating hour lines: H is the local hour angle in degrees (negative
  before local apparent noon), H0 the semi-diurnal arc from SemiDiurnalArc. }
function TemporalFromHourAngle(const AHDeg, AH0Deg: Double): Double;
function BabylonianFromHourAngle(const AHDeg, AH0Deg: Double): Double;
function ItalianFromHourAngle(const AHDeg, AH0Deg: Double): Double;

function HourCountToStr(AHours: Double): string;

implementation

{ ============================================================
  THourSystems
  ============================================================ }

function THourSystems.TemporalOrdinal: Integer;
begin
  if not (Valid and IsDaytime) then Exit(0);
  Result := Trunc(Temporal) + 1;
  if Result > 12 then Result := 12;
end;

function THourSystems.BabylonianOrdinal: Integer;
begin
  if not Valid then Exit(0);
  Result := Trunc(Babylonian) + 1;
  if Result > 24 then Result := 24;
end;

function THourSystems.ItalianOrdinal: Integer;
begin
  if not Valid then Exit(0);
  Result := Trunc(Italian) + 1;
  if Result > 24 then Result := 24;
end;

{ ============================================================
  Core computation
  ============================================================ }

function ComputeHourSystems(const ANow, ASunrise, ASunset: Double;
  const AHasRiseSet: Boolean): THourSystems;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Valid := AHasRiseSet;
  if not Result.Valid then Exit;

  { NormalizeHours folds every difference into [0, 24), which is exactly the
    day-wrap handling these quantities need. }
  Result.DayLength    := NormalizeHours(ASunset - ASunrise);
  Result.NightLength  := 24.0 - Result.DayLength;
  Result.SinceSunrise := NormalizeHours(ANow    - ASunrise);
  Result.UntilSunset  := NormalizeHours(ASunset - ANow);

  { Degenerate day lengths would divide by ~zero; treat as polar. }
  if (Result.DayLength < 1e-6) or (Result.NightLength < 1e-6) then
  begin
    Result.Valid := False;
    Exit;
  end;

  Result.IsDaytime       := Result.SinceSunrise <= Result.DayLength;
  Result.TemporalLength  := Result.DayLength   / 12.0;
  Result.NocturnalLength := Result.NightLength / 12.0;

  { Babylonian: equal hours from sunrise. }
  Result.Babylonian := Result.SinceSunrise;

  { Italian: equal hours, the 24th ending at sunset. Expressed as hours
    remaining rather than as elapsed-since-previous-sunset, which is both the
    dial-line construction and free of any dependence on yesterday's data. }
  Result.Italian := 24.0 - Result.UntilSunset;

  { Temporal: the daylight span in twelfths, or the night span if the sun is
    down. Nocturnal hours are the same idea applied to the dark half. }
  if Result.IsDaytime then
    Result.Temporal := 12.0 * Result.SinceSunrise / Result.DayLength
  else
    Result.Nocturnal := 12.0 * (Result.SinceSunrise - Result.DayLength)
                             / Result.NightLength;
end;

{ ============================================================
  Analytic forms for hour-line generation
  ============================================================ }

function SemiDiurnalArc(const ALatitudeDeg, ADeclinationDeg: Double;
  out AH0Deg: Double; const AHorizonAlt: Double): Boolean;
var
  LNum, LDen, LCos: Double;
begin
  AH0Deg := 0.0;
  LDen := Cos(ALatitudeDeg * DEG_TO_RAD) * Cos(ADeclinationDeg * DEG_TO_RAD);
  if Abs(LDen) < 1e-12 then Exit(False);

  LNum := Sin(AHorizonAlt * DEG_TO_RAD)
        - Sin(ALatitudeDeg * DEG_TO_RAD) * Sin(ADeclinationDeg * DEG_TO_RAD);
  LCos := LNum / LDen;
  if Abs(LCos) > 1.0 then Exit(False);   // circumpolar or never rises

  AH0Deg := ArcCos(LCos) * RAD_TO_DEG;
  Result := True;
end;

function TemporalFromHourAngle(const AHDeg, AH0Deg: Double): Double;
begin
  if Abs(AH0Deg) < 1e-9 then Exit(0.0);
  Result := 6.0 * (1.0 + AHDeg / AH0Deg);
end;

function BabylonianFromHourAngle(const AHDeg, AH0Deg: Double): Double;
begin
  Result := (AHDeg + AH0Deg) / 15.0;
end;

function ItalianFromHourAngle(const AHDeg, AH0Deg: Double): Double;
begin
  Result := 24.0 - (AH0Deg - AHDeg) / 15.0;
end;

{ ============================================================
  Formatting
  ============================================================ }

function HourCountToStr(AHours: Double): string;
var
  LH, LM, LSign: Integer;
begin
  LSign := 1;
  if AHours < 0 then
  begin
    AHours := Abs(AHours);
    LSign := -1;
  end;
  LH := Trunc(AHours);
  LM := Round((AHours - LH) * 60.0);
  if LM = 60 then begin LM := 0; Inc(LH); end;
  Result := Format('%.2d:%.2d', [LH * LSign, LM]);
end;

end.
