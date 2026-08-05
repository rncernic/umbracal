unit UHelper;

{$mode ObjFPC}{$H+}

{
  Unit UHelper

  Common mathematical and formatting helper routines used throughout
  the application.
}


interface

uses
  Classes, SysUtils, Math;

const
  { Mathematical constants }
  DEG_TO_RAD = Pi / 180.0;
  RAD_TO_DEG = 180.0 / Pi;
  TWO_PI     = 2.0 * Pi;

  { Angular constants }
  FULL_CIRCLE = 360.0;
  HALF_CIRCLE = 180.0;
  HOURS_PER_DAY = 24.0;

  { Astronomical constants }
  J2000      = 2451545.0;

type
  { Formatting style used by DegToDMS. }
  TAngleStyle = (asSigned, asLatitude, asLongitude, asUnsigned);

  { Normalize an angle into the interval [0°, 360°). }
  function Normalize360(AAngle: Double): Double;

  { Normalize an angle into the interval (-180°, 180°]. }
  function Normalize180(AAngle: Double): Double;

  { Normalize an angle in radians into the interval [0, 2π). }
  function Normalize2Pi(AAngle: Double): Double;

  { Normalize an angle in radians into the interval (-π, π]. }
  function NormalizePi(ARadians: Double): Double;

  { Smallest signed rotation from angle A to angle B. }
  function AngularDelta(AA, AB: Double): Double;

  { Normalize a fractional value into the interval [0,1). }
  function NormalizeFraction(AValue: Double): Double;

  { Dip of the visible horizon (degrees) for the given observer elevation. }
  function HorizonDip(AElevationMeters: Double): Double;

  { Apply standard atmospheric refraction correction to an altitude. }
  function RefractAltitude(AAltitude: Double): Double;

  { Normalize time expressed in decimal hours into the interval [0,24). }
  function NormalizeHours(AHours: Double): Double;

  { Convert Julian Day to ISO date (YYYY-MM-DD). }
  function JDToISO(AJD: Double): string;

  { Format a Julian Day for display. }
  function JDToStrFull(AJD: Double): string;

  {
    Convert decimal degrees to degrees/minutes[/seconds].

    When ASeconds=False the output contains only degrees and minutes.
    When ASeconds=True seconds are rounded once to avoid values such as
    59' 60.00".
  }
  function DegToDMS(
    const ADegrees: Double;
    const AStyle: TAngleStyle = asSigned;
    const ADecimals: Integer = 0;
    const ASeconds: Boolean = False
  ): string;

implementation

// [0, 360)
function Normalize360(AAngle: Double): Double;
begin
  Result := AAngle - FULL_CIRCLE * Floor(AAngle / FULL_CIRCLE);
end;

// (-180, 180]
function Normalize180(AAngle: Double): Double;
begin
  AAngle := fmod(AAngle, FULL_CIRCLE);
  if AAngle <= -HALF_CIRCLE then
    AAngle := AAngle + FULL_CIRCLE
  else if AAngle > HALF_CIRCLE then
    AAngle := AAngle - FULL_CIRCLE;
  Result := AAngle;
end;

// [0, 2Pi)
function Normalize2Pi(AAngle: Double): Double;
begin
  Result := AAngle - (2.0 * Pi) * Floor(AAngle / (2.0 * Pi));
end;

// (-Pi, Pi]
function NormalizePi(ARadians: Double): Double;
begin
  ARadians := fmod(ARadians, TWO_PI);
  if ARadians <= -Pi then
    ARadians := ARadians + TWO_PI
  else if ARadians > Pi then
    ARadians := ARadians - TWO_PI;
  Result := ARadians;
end;

// How far do I rotate from a to b?
function AngularDelta(AA,AB: Double): Double;
begin
  Result := Normalize180(AB - AA);
end;

function NormalizeFraction(AValue: Double): Double;
begin
  Result := AValue - Floor(AValue);
  if Result < 0 then Result := Result + 1;
end;

function HorizonDip(AElevationMeters: Double): Double;
begin
  Result := -0.0293 * Sqrt(AElevationMeters);
end;

function RefractAltitude(AAltitude: Double): Double;
begin
  if (AAltitude > -1) and (AAltitude < 90) then
    Result := AAltitude + (1.02 / Tan((AAltitude + 10.3 / (AAltitude + 5.11)) * DEG_TO_RAD)) / 60
  else
    Result := AAltitude;
end;

function NormalizeHours(AHours: Double): Double;
begin
  Result := AHours - HOURS_PER_DAY * Floor(AHours / HOURS_PER_DAY);
end;

function JDToISO(AJD: Double): string;
var
  LJD:   Double;
  LZ, LA, LB, LC, LD, LE, LYear, LMonth: Integer;
  LAlpha, LF: Double;
  LDay:  Integer;
begin
  LJD    := AJD + 0.5;
  LZ     := Trunc(LJD);
  LF     := LJD - LZ;

  LAlpha := Trunc((LZ - 1867216.25) / 36524.25);
  LA     := LZ + 1 + Trunc(LAlpha) - Trunc(LAlpha / 4);
  LB     := LA + 1524;
  LC     := Floor((LB - 122.1) / 365.25);
  LD     := Floor(365.25 * LC);
  LE     := Trunc((LB - LD) / 30.6001);

  LDay   := LB - LD - Trunc(30.6001 * LE);

  if LE < 14 then LMonth := LE - 1 else LMonth := LE - 13;
  if LMonth > 2 then LYear := LC - 4716 else LYear := LC - 4715;

  Result := Format('%d-%2.2d-%2.2d', [LYear, LMonth, LDay]);
end;

function JDToStrFull(AJD: Double): string;
begin
  Result := Format('%.7f', [AJD]);
end;

function DegToDMS(const ADegrees: Double; const AStyle: TAngleStyle;
  const ADecimals: Integer; const ASeconds: Boolean): string;
var
  LNeg:  Boolean;
  LTicks, LScale: Int64;
  LD, LM: Integer;
  LS:     Double;
  LPre, LSuf: string;
begin
  LNeg := ADegrees < 0;

  { Round once, in units of the smallest displayed digit, so the carry
    propagates instead of showing as 60.00". }
  LScale := Round(IntPower(10, ADecimals));
  LTicks := Round(Abs(ADegrees) * 3600.0 * LScale);

  LS := (LTicks mod (60 * LScale)) / LScale;
  LTicks := LTicks div (60 * LScale);
  LM := LTicks mod 60;
  LTicks := LTicks div 60;
  LD := LTicks;

  LPre := '';
  LSuf := '';
  case AStyle of
    asSigned:    if LNeg then LPre := '-';
    asLatitude:  if LNeg then LSuf := ' S' else LSuf := ' N';
    asLongitude: if LNeg then LSuf := ' W' else LSuf := ' E';
    asUnsigned:  ;
  end;

  if ASeconds Then
    Result := Format('%s%d° %.2d'' %.*f"%s',
                     [LPre, LD, LM, ADecimals, LS, LSuf])
  else
     Result := Format('%s%d° %.2d''', [LPre, LD, LM]);

end;

end.

