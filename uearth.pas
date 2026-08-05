unit UEarth;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,
  UHelper,
  UNutation;


procedure Nutation(t:Double; out deltaPhi, deltaEps, eps0: Double);

implementation

// Nutation calculates deltas in hours and eps0 in degrees
// Meeus - pg. 132
procedure Nutation(t:Double; out deltaPhi, deltaEps, eps0: Double);
var
  d, m, mprime, f, omega: Double;
  x: Double;
  i: Integer;
begin
  deltaPhi := 0;
  deltaEps := 0;

  // Mean elongation of Moon from Sun
  d      := Normalize360(297.85036 + 445267.111480*t - 0.0019142*t*t + t*t*t/189474.0);
  // Mean anomaly of the Sun
  m      := Normalize360(357.52772 + 35999.050340*t - 0.0001603*t*t + t*t*t/300000.0);
  // Mean anomaly of the Moon
  mprime := Normalize360(134.96298 + 477198.867398*t + 0.0086972*t*t + t*t*t/56250.0);
  // Moon's argument of latitude
  f      := Normalize360(93.27191 + 483202.017538*t - 0.0036825*t*t + t*t*t/327270.0);
  // Longitude of the ascending node of the Moon's mean orbit
  omega  := Normalize360(125.04452 - 1934.136261*t + 0.0020708*t*t + t*t*t/450000.0);

  for i := 0 to NUTATION_COUNT - 1 do
  begin
    x := nutationArgs[i][0]*d +
         nutationArgs[i][1]*m +
         nutationArgs[i][2]*mprime +
         nutationArgs[i][3]*f +
         nutationArgs[i][4]*omega;

    deltaPhi := deltaPhi + (nutationSinCoeff[i][0] + nutationSinCoeff[i][1]*t) * Sin(x * DEG_TO_RAD);
    deltaEps := deltaEps + (nutationCosCoeff[i][0] + nutationCosCoeff[i][1]*t) * Cos(x * DEG_TO_RAD);
  end;

  // Convert results from 0.0001 seconds to hours
  deltaPhi := deltaPhi / (1e4 * 3600.0);
  deltaEps := deltaEps / (1e4 * 3600.0);

  // Mean obliquity of the ecliptic - Meeus Eq. 21.2 pg. 135
  eps0 := 23.0 + 26.0/60.0 + (21.448 - 46.8150*t - 0.00059*t*t + 0.001813*t*t*t) / 3600.0;
end;

end.

