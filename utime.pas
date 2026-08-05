unit UTime;

{ Time scales and time formatting for the astro library.

  Holds everything that converts between UT, TT, sidereal and apparent solar
  time, plus the two corrections a dialist needs (equation of time and
  longitude correction). Depends only on a_helper, so it can be used from
  either the engine or the UI without pulling in the solar code.

  Convention used throughout: longitude is positive EAST. }

{$mode ObjFPC}{$H+}
{$MODESWITCH ADVANCEDRECORDS}

interface

uses
  Classes, SysUtils, Math,
  UHelper;

type
  { TTimeScales — the UT/TT pair for one instant }
  TTimeScales = record
    JD_UT:     Double;   // Julian Date, Universal Time
    JD_TT:     Double;   // Julian Date, Terrestrial Time (= JD_UT + dT)
    JC_UT:     Double;   // Julian centuries from J2000, UT based
    JC_TT:     Double;   // Julian centuries from J2000, TT based
    DeltaTSec: Double;   // TT - UT, seconds
    DayStart:  Double;   // JD_UT at 0h of the same UT day
    UTHours:   Double;   // hours elapsed since DayStart, [0, 24)
  end;

{ ---- Delta T ------------------------------------------------------------ }

{ Espenak & Meeus polynomial expressions. Accurate to a second or two over
  1600..2050 and degrading outside that. Note the 2005..2050 branch is a
  forward extrapolation fitted before the Earth's recent spin-up, so it runs
  a few seconds high for the present decade — pass an override if you have a
  current IERS value. }
function DeltaTSeconds(const ADecimalYear: Double): Double;

function JDToDecimalYear(const AJD: Double): Double;

{ ADeltaTOverride < 0 means "use the polynomial". }
function BuildTimeScales(const AJD_UT: Double;
  const ADeltaTOverride: Double = -1.0): TTimeScales;

{ ---- Sidereal time ------------------------------------------------------ }

{ Greenwich MEAN sidereal time, degrees. Meeus Eq. 12.4. Takes UT, not TT. }
function GreenwichMeanSiderealDeg(const AJD_UT: Double): Double;

{ Greenwich APPARENT sidereal time — mean plus the equation of the equinoxes.
  ADeltaPsiDeg and ATrueObliquityDeg both in degrees. }
function GreenwichApparentSiderealDeg(const AJD_UT,
  ADeltaPsiDeg, ATrueObliquityDeg: Double): Double;

function LocalSiderealDeg(const AGreenwichSiderealDeg,
  ALongitudeDeg: Double): Double;

{ ---- Solar time corrections --------------------------------------------- }

{ Equation of time in MINUTES, apparent minus mean. Meeus Eq. 28.3.
  Takes TT-based Julian centuries. }
function EquationOfTimeMinutes(const AJC_TT: Double): Double;

{ Longitude correction in MINUTES: how far the local meridian runs ahead of
  the zone meridian. Positive means local apparent noon is earlier than zone
  noon. }
function LongitudeCorrectionMinutes(const ALongitudeDeg,
  AZoneHours: Double): Double;

{ ---- Calendar helpers --------------------------------------------------- }

function DayOfWeekFromJD(const AJD: Double): Integer;   // 0 = Sunday
function DayOfWeekName(const AIndex: Integer): string;
function JDDayStart(const AJD: Double): Double;         // JD at 0h UT

{ ---- Formatting --------------------------------------------------------- }

function HoursToHM(const AHours: Double): string;       // 14:35
function HoursToHMS(const AHours: Double): string;      // 14:35:12
function DurationToStr(const AHours: Double): string;   // 8h 10m
function MinutesToSignedStr(const AMinutes: Double): string;  // +3m 42s
function DegToHMS(const ADegrees: Double): string;      // 15h 24m 09s

implementation

{ ============================================================
  Delta T
  ============================================================ }

function JDToDecimalYear(const AJD: Double): Double;
begin
  { Adequate for Delta T, which is a slowly varying quantity. }
  Result := 2000.0 + (AJD - J2000) / 365.25;
end;

function DeltaTSeconds(const ADecimalYear: Double): Double;
var
  LY, Lt, Lu: Double;
begin
  LY := ADecimalYear;

  if (LY >= 2005.0) and (LY < 2050.0) then
  begin
    Lt := LY - 2000.0;
    Result := 62.92 + 0.32217 * Lt + 0.005589 * Lt * Lt;
  end
  else if (LY >= 1986.0) and (LY < 2005.0) then
  begin
    Lt := LY - 2000.0;
    Result := 63.86 + Lt * (0.3345 + Lt * (-0.060374 + Lt * (0.0017275
              + Lt * (0.000651814 + Lt * 0.00002373599))));
  end
  else if (LY >= 1961.0) and (LY < 1986.0) then
  begin
    Lt := LY - 1975.0;
    Result := 45.45 + 1.067 * Lt - Lt * Lt / 260.0 - Lt * Lt * Lt / 718.0;
  end
  else if (LY >= 1941.0) and (LY < 1961.0) then
  begin
    Lt := LY - 1950.0;
    Result := 29.07 + 0.407 * Lt - Lt * Lt / 233.0 + Lt * Lt * Lt / 2547.0;
  end
  else if (LY >= 1920.0) and (LY < 1941.0) then
  begin
    Lt := LY - 1920.0;
    Result := 21.20 + Lt * (0.84493 + Lt * (-0.076100 + Lt * 0.0020936));
  end
  else if (LY >= 1900.0) and (LY < 1920.0) then
  begin
    Lt := LY - 1900.0;
    Result := -2.79 + Lt * (1.494119 + Lt * (-0.0598939 + Lt * (0.0061966
              + Lt * -0.000197)));
  end
  else if (LY >= 1860.0) and (LY < 1900.0) then
  begin
    Lt := LY - 1860.0;
    Result := 7.62 + Lt * (0.5737 + Lt * (-0.251754 + Lt * (0.01680668
              + Lt * (-0.0004473624 + Lt / 233174.0))));
  end
  else if (LY >= 1800.0) and (LY < 1860.0) then
  begin
    Lt := LY - 1800.0;
    Result := 13.72 + Lt * (-0.332447 + Lt * (0.0068612 + Lt * (0.0041116
              + Lt * (-0.00037436 + Lt * (0.0000121272 + Lt * (-0.0000001699
              + Lt * 0.000000000875))))));
  end
  else if (LY >= 1700.0) and (LY < 1800.0) then
  begin
    Lt := LY - 1700.0;
    Result := 8.83 + Lt * (0.1603 + Lt * (-0.0059285 + Lt * (0.00013336
              - Lt / 1174000.0)));
  end
  else if (LY >= 1600.0) and (LY < 1700.0) then
  begin
    Lt := LY - 1600.0;
    Result := 120.0 - 0.9808 * Lt - 0.01532 * Lt * Lt + Lt * Lt * Lt / 7129.0;
  end
  else if (LY >= 2050.0) and (LY < 2150.0) then
  begin
    Lu := (LY - 1820.0) / 100.0;
    Result := -20.0 + 32.0 * Lu * Lu - 0.5628 * (2150.0 - LY);
  end
  else
  begin
    { Long-term parabola, valid either side of the fitted range. }
    Lu := (LY - 1820.0) / 100.0;
    Result := -20.0 + 32.0 * Lu * Lu;
  end;
end;

function JDDayStart(const AJD: Double): Double;
begin
  Result := Floor(AJD - 0.5) + 0.5;
end;

function BuildTimeScales(const AJD_UT: Double;
  const ADeltaTOverride: Double): TTimeScales;
begin
  Result.JD_UT := AJD_UT;

  if ADeltaTOverride >= 0.0 then
    Result.DeltaTSec := ADeltaTOverride
  else
    Result.DeltaTSec := DeltaTSeconds(JDToDecimalYear(AJD_UT));

  Result.JD_TT    := AJD_UT + Result.DeltaTSec / 86400.0;
  Result.JC_UT    := (Result.JD_UT - J2000) / 36525.0;
  Result.JC_TT    := (Result.JD_TT - J2000) / 36525.0;
  Result.DayStart := JDDayStart(AJD_UT);
  Result.UTHours  := (AJD_UT - Result.DayStart) * 24.0;
end;

{ ============================================================
  Sidereal time
  ============================================================ }

function GreenwichMeanSiderealDeg(const AJD_UT: Double): Double;
var
  LT, LTheta: Double;
begin
  LT := (AJD_UT - J2000) / 36525.0;
  LTheta := 280.46061837
            + 360.98564736629 * (AJD_UT - J2000)
            + 0.000387933 * LT * LT
            - LT * LT * LT / 38710000.0;
  Result := Normalize360(LTheta);
end;

function GreenwichApparentSiderealDeg(const AJD_UT,
  ADeltaPsiDeg, ATrueObliquityDeg: Double): Double;
begin
  { Equation of the equinoxes: dPsi * cos(true obliquity). }
  Result := Normalize360(GreenwichMeanSiderealDeg(AJD_UT)
            + ADeltaPsiDeg * Cos(ATrueObliquityDeg * DEG_TO_RAD));
end;

function LocalSiderealDeg(const AGreenwichSiderealDeg,
  ALongitudeDeg: Double): Double;
begin
  Result := Normalize360(AGreenwichSiderealDeg + ALongitudeDeg);
end;

{ ============================================================
  Solar time corrections
  ============================================================ }

function EquationOfTimeMinutes(const AJC_TT: Double): Double;
var
  LL0, LM, LE, LY, LCapE: Double;
begin
  LL0 := Normalize360(280.46646 + 36000.76983 * AJC_TT
                      + 0.0003032 * AJC_TT * AJC_TT) * DEG_TO_RAD;
  LM  := Normalize360(357.52911 + 35999.05029 * AJC_TT
                      - 0.0001537 * AJC_TT * AJC_TT) * DEG_TO_RAD;
  LE  := 0.016708634 - AJC_TT * (0.000042037 + 0.0000001267 * AJC_TT);

  LY  := Tan(23.43929111 / 2.0 * DEG_TO_RAD);
  LY  := LY * LY;

  LCapE := LY * Sin(2.0 * LL0)
           - 2.0 * LE * Sin(LM)
           + 4.0 * LE * LY * Sin(LM) * Cos(2.0 * LL0)
           - 0.5 * LY * LY * Sin(4.0 * LL0)
           - 1.25 * LE * LE * Sin(2.0 * LM);

  Result := LCapE * RAD_TO_DEG * 4.0;   // degrees -> minutes of time
end;

function LongitudeCorrectionMinutes(const ALongitudeDeg,
  AZoneHours: Double): Double;
begin
  Result := (ALongitudeDeg - 15.0 * AZoneHours) * 4.0;
end;

{ ============================================================
  Calendar helpers
  ============================================================ }

function DayOfWeekFromJD(const AJD: Double): Integer;
begin
  Result := Trunc(AJD + 1.5) mod 7;
  if Result < 0 then Inc(Result, 7);
end;

function DayOfWeekName(const AIndex: Integer): string;
const
  CNames: array[0..6] of string =
    ('Sunday', 'Monday', 'Tuesday', 'Wednesday',
     'Thursday', 'Friday', 'Saturday');
begin
  if (AIndex >= 0) and (AIndex <= 6) then
    Result := CNames[AIndex]
  else
    Result := '';
end;

{ ============================================================
  Formatting
  ============================================================ }

function HoursToHM(const AHours: Double): string;
var
  LH, LM: Integer;
  LV: Double;
begin
  LV := NormalizeHours(AHours);
  LH := Trunc(LV);
  LM := Round((LV - LH) * 60.0);
  if LM = 60 then begin LM := 0; LH := (LH + 1) mod 24; end;
  Result := Format('%.2d:%.2d', [LH, LM]);
end;

function HoursToHMS(const AHours: Double): string;
var
  LH, LM, LS: Integer;
  LV: Double;
begin
  LV := NormalizeHours(AHours);
  LS := Round(LV * 3600.0);
  LH := LS div 3600;  LS := LS mod 3600;
  LM := LS div 60;    LS := LS mod 60;
  if LH = 24 then LH := 0;
  Result := Format('%.2d:%.2d:%.2d', [LH, LM, LS]);
end;

function DurationToStr(const AHours: Double): string;
var
  LH, LM: Integer;
begin
  LH := Trunc(AHours);
  LM := Round((AHours - LH) * 60.0);
  if LM = 60 then begin LM := 0; Inc(LH); end;
  Result := Format('%dh %.2dm', [LH, LM]);
end;

function MinutesToSignedStr(const AMinutes: Double): string;
var
  LSign: string;
  LTotal, LM, LS: Integer;
begin
  if AMinutes < 0 then LSign := '-' else LSign := '+';
  LTotal := Round(Abs(AMinutes) * 60.0);
  LM := LTotal div 60;
  LS := LTotal mod 60;
  Result := Format('%s%dm %.2ds', [LSign, LM, LS]);
end;

function DegToHMS(const ADegrees: Double): string;
begin
  Result := HoursToHMS(Normalize360(ADegrees) / 15.0);
end;

end.
