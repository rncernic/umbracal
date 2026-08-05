unit UAngle;

{
  Unit UAngle

  Fundamental angle and observer types used across the application.
}

{$mode ObjFPC}{$H+}
{$MODESWITCH ADVANCEDRECORDS}

interface

uses
  Classes, SysUtils, StrUtils,
  UHelper;

type
  { TAngle — a degree value with built-in trig and formatting }
  TAngle = record
    Degrees: Double;

    function Rad:   Double;
    function Sin:   Double;
    function Cos:   Double;
    function ToDMS: string;
    function ToPi:  string;
  end;

  { TObserver — geographic location of the observer }
  TObserver = record
    Latitude:  TAngle;   // +N / -S
    Longitude: TAngle;   // +E / -W
    Elevation: Double;   // metres above sea level
  end;

  { TTwilight — rise/set/culmination for one altitude threshold }
  TTwilight = record
    Rise:         Double;  // decimal hours UTC
    SetTime:      Double;  // decimal hours UTC
    Culmination:  Double;  // decimal hours UTC (solar noon)
    TwilightType: string;  // 'Normal' | 'PolarDay' | 'PolarNight'
  end;

  { TRiseSet — full twilight bundle for one day }
  TRiseSet = record
    Sunrise:      TTwilight;
    Civil:        TTwilight;
    Nautical:     TTwilight;
    Astronomical: TTwilight;
  end;

  { THorizontal — topocentric altitude / azimuth }
  THorizontal = record
    Altitude:     Double;  // degrees
    AzimuthNav:   Double;  // degrees, N=0 clockwise
    AzimuthAstro: Double;  // degrees, S=0 clockwise
  end;

  { TGeocentric — heliocentric-to-geocentric ecliptic coords }
  TGeocentric = record
    Longitude:    Double;  // radians
    Latitude:     Double;  // radians
    RadiusVector: Double;  // AU
  end;

  { TEquatorial — apparent equatorial coordinates }
  TEquatorial = record
    RightAscensionRad: Double;
    DeclinationRad:    Double;
    RightAscensionDeg: Double;
    DeclinationDeg:    Double;
  end;

  { TSunEphemeris — basic ephemeris output }
  TSunEphemeris = record
    RA:       Double;  // degrees
    Dec:      Double;  // degrees
    Distance: Double;  // AU
  end;

implementation

{ Convert angle from degrees to radians. }
function TAngle.Rad: Double;
begin
  Result := Degrees * DEG_TO_RAD;
end;

{ Calculate sine of the angle. }
function TAngle.Sin: Double;
begin
  Result := System.Sin(Rad);
end;

{ Calculate cossine of the angle. }
function TAngle.Cos: Double;
begin
  Result := System.Cos(Rad);
end;

{ Convert angle to degrees/minutes[/seconds]. }
function TAngle.ToDMS: string;
var
  LAbsDeg:  Double;
  LDeg, LMin: Integer;
  LSec:     Double;
  LSign:    string;
begin
  LAbsDeg := System.Abs(Degrees);
  LSign   := IfThen(Degrees < 0, '-', '');
  LDeg    := Trunc(LAbsDeg);
  LMin    := Trunc((LAbsDeg - LDeg) * 60);
  LSec    := ((LAbsDeg - LDeg) * 60 - LMin) * 60;
  Result  := Format('%s%d° %d'' %.2f"', [LSign, LDeg, LMin, LSec]);
end;

{ Convert angle to multiples of Pi. }
function TAngle.ToPi: string;
var
  LRatio: Double;
begin
  LRatio := Rad / Pi;
  if System.Abs(LRatio - 2.0) < 1e-6 then Exit('2π');
  if System.Abs(LRatio - 1.0) < 1e-6 then Exit('π');
  if System.Abs(LRatio - 0.5) < 1e-6 then Exit('π/2');
  Result := Format('%.4fπ', [LRatio]);
end;

end.
