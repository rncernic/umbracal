unit UJDEdit;

{ TJDEdit — a TEdit subclass for entering astronomical dates.
  Accepts a wide range of input formats and stores the result as a
  Julian Date (Double), covering dates from deep antiquity to far future.

  Accepted input formats (proleptic Gregorian calendar):
    2025-06-21              ISO 8601
    21/06/2025              DD/MM/YYYY
    21.06.2025              DD.MM.YYYY
    June 21, 2025           Long form
    21 Jun 2025             Short month name
    JD 2460847.5            Julian Date literal
    -4712-01-01             Negative year (BCE proleptic Gregorian)

  On exit the field is reformatted to ISO 8601: YYYY-MM-DD
  (or "JD xxxxxxxxx.x" if the user entered a JD literal).

  The BCE boundary: year 0 in proleptic Gregorian = 1 BC in astronomical
  year numbering. Years BCE are entered as negative integers.
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StdCtrls, Graphics, RegExpr, Math;

type
  TJDEdit = class(TEdit)
  private
    FJulianDate: Double;   // current value as Julian Date
    FValid: Boolean;
    FShowAsJD: Boolean;    // if True, reformat as "JD xxxxxxx.x" on exit

    function  ParseInput(const AInput: string; out AJD: Double): Boolean;
    function  ParseISO(const S: string; out AJD: Double): Boolean;
    function  ParseDMY(const S: string; ASep: Char; out AJD: Double): Boolean;
    function  ParseLongMonth(const S: string; out AJD: Double): Boolean;
    function  ParseJDLiteral(const S: string; out AJD: Double): Boolean;

    function  CalendarToJD(AYear, AMonth: Integer; ADay: Double): Double;
    function  JDToCalendar(AJD: Double;
                out AYear, AMonth: Integer; out ADay: Double): Boolean;

    function  MonthNameToNumber(const AName: string): Integer;
    function  FormatDate(AJD: Double): string;

    procedure SetJulianDate(AValue: Double);
    procedure Validate;
  protected
    procedure Change; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;

    property JulianDate: Double  read FJulianDate write SetJulianDate;
    property IsValid:    Boolean read FValid;
  published
    property ShowAsJD: Boolean read FShowAsJD write FShowAsJD default False;
  end;

implementation

{ ============================================================
  Julian Day arithmetic — no TDateTime involved at all.
  Uses the standard astronomical algorithm (Meeus, Ch.7).
  Valid for any proleptic Gregorian date.
  Year 0 = 1 BC, year -1 = 2 BC, etc.
  ============================================================ }

function TJDEdit.CalendarToJD(AYear, AMonth: Integer; ADay: Double): Double;
var
  LY, LM: Integer;
  LA, LB: Integer;
begin
  if AMonth <= 2 then
  begin
    LY := AYear - 1;
    LM := AMonth + 12;
  end
  else
  begin
    LY := AYear;
    LM := AMonth;
  end;

  { Gregorian calendar correction }
  LA := Trunc(LY / 100);
  LB := 2 - LA + Trunc(LA / 4);

  Result := Trunc(365.25  * (LY + 4716))
          + Trunc(30.6001 * (LM + 1))
          + ADay + LB - 1524.5;
end;

function TJDEdit.JDToCalendar(AJD: Double;
  out AYear, AMonth: Integer; out ADay: Double): Boolean;
var
  LJD: Double;
  LZ, LA, LB, LC, LD, LE: Integer;
  LF, LAlpha: Double;
begin
  Result := True;
  LJD := AJD + 0.5;
  LZ  := Trunc(LJD);
  LF  := LJD - LZ;          // true fractional day

  { Always use proleptic Gregorian correction }
  LAlpha := Trunc((LZ - 1867216.25) / 36524.25);
  LA     := LZ + 1 + Trunc(LAlpha) - Trunc(LAlpha / 4);

  LB := LA + 1524;

  { Floor division required here — Trunc is wrong for negative LC/LD }
  LC := Floor((LB - 122.1) / 365.25);
  LD := Floor(365.25 * LC);

  LE := Trunc((LB - LD) / 30.6001);

  ADay := (LB - LD - Trunc(30.6001 * LE)) + LF;

  if LE < 14 then AMonth := LE - 1
             else AMonth := LE - 13;

  if AMonth > 2 then AYear := LC - 4716
                else AYear := LC - 4715;
end;

{ ============================================================
  Month name lookup
  ============================================================ }

function TJDEdit.MonthNameToNumber(const AName: string): Integer;
const
  CShort: array[1..12] of string = (
    'JAN','FEB','MAR','APR','MAY','JUN',
    'JUL','AUG','SEP','OCT','NOV','DEC');
  CLong: array[1..12] of string = (
    'JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE',
    'JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER');
var
  LUp: string;
  LIdx: Integer;
begin
  LUp := UpperCase(Trim(AName));
  for LIdx := 1 to 12 do
    if (LUp = CShort[LIdx]) or (LUp = CLong[LIdx]) then
      Exit(LIdx);
  Result := 0;
end;

{ ============================================================
  Individual parsers
  ============================================================ }

{ ISO 8601: YYYY-MM-DD  or  -YYYY-MM-DD }
function TJDEdit.ParseISO(const S: string; out AJD: Double): Boolean;
var
  LR: TRegExpr;
  LY, LMo, LD: Integer;
begin
  Result := False;
  LR := TRegExpr.Create('^(-?\d{4,})-(\d{2})-(\d{2})$');
  try
    if LR.Exec(Trim(S)) then
    begin
      LY  := StrToIntDef(LR.Match[1], 0);
      LMo := StrToIntDef(LR.Match[2], 0);
      LD  := StrToIntDef(LR.Match[3], 0);
      if (LMo >= 1) and (LMo <= 12) and (LD >= 1) and (LD <= 31) then
      begin
        AJD    := CalendarToJD(LY, LMo, LD);
        Result := True;
      end;
    end;
  finally
    LR.Free;
  end;
end;

{ Slash or dot-separated: DD/MM/YYYY or DD.MM.YYYY }
function TJDEdit.ParseDMY(const S: string; ASep: Char; out AJD: Double): Boolean;
var
  LParts: TStringList;
  LY, LMo, LD: Integer;
begin
  Result := False;
  LParts := TStringList.Create;
  try
    LParts.Delimiter     := ASep;
    LParts.DelimitedText := S;
    if LParts.Count = 3 then
    begin
      LD  := StrToIntDef(LParts[0], 0);
      LMo := StrToIntDef(LParts[1], 0);
      LY  := StrToIntDef(LParts[2], 0);
      if (LMo >= 1) and (LMo <= 12) and (LD >= 1) and (LD <= 31) then
      begin
        AJD    := CalendarToJD(LY, LMo, LD);
        Result := True;
      end;
    end;
  finally
    LParts.Free;
  end;
end;

{ "21 Jun 2025"  or  "June 21, 2025" }
function TJDEdit.ParseLongMonth(const S: string; out AJD: Double): Boolean;
var
  LR: TRegExpr;
  LMo, LY, LD: Integer;
begin
  Result := False;

  { "DD MonthName YYYY" }
  LR := TRegExpr.Create('^\s*(\d{1,2})\s+([A-Za-z]+)\s+(-?\d{4,})\s*$');
  try
    if LR.Exec(S) then
    begin
      LD  := StrToIntDef(LR.Match[1], 0);
      LMo := MonthNameToNumber(LR.Match[2]);
      LY  := StrToIntDef(LR.Match[3], 0);
      if (LMo > 0) and (LD >= 1) and (LD <= 31) then
      begin
        AJD    := CalendarToJD(LY, LMo, LD);
        Result := True;
        Exit;
      end;
    end;
  finally
    LR.Free;
  end;

  { "MonthName DD, YYYY" }
  LR := TRegExpr.Create('^\s*([A-Za-z]+)\s+(\d{1,2}),?\s+(-?\d{4,})\s*$');
  try
    if LR.Exec(S) then
    begin
      LMo := MonthNameToNumber(LR.Match[1]);
      LD  := StrToIntDef(LR.Match[2], 0);
      LY  := StrToIntDef(LR.Match[3], 0);
      if (LMo > 0) and (LD >= 1) and (LD <= 31) then
      begin
        AJD    := CalendarToJD(LY, LMo, LD);
        Result := True;
      end;
    end;
  finally
    LR.Free;
  end;
end;

{ "JD 2460847.5" or "JD2460847.5" }
function TJDEdit.ParseJDLiteral(const S: string; out AJD: Double): Boolean;
var
  LR: TRegExpr;
  LFS: TFormatSettings;
begin
  Result := False;
  LFS := DefaultFormatSettings;
  LFS.DecimalSeparator := '.';

  LR := TRegExpr.Create('^\s*JD\s*(-?\d+(?:\.\d*)?)\s*$');
  try
    if LR.Exec(UpperCase(S)) then
    begin
      Result := TryStrToFloat(LR.Match[1], AJD, LFS);
      FShowAsJD := True;  // remember the user prefers JD display
    end;
  finally
    LR.Free;
  end;
end;

{ Master parser — tries each format in order }
function TJDEdit.ParseInput(const AInput: string; out AJD: Double): Boolean;
var
  S: string;
begin
  S := Trim(AInput);

  Result := ParseJDLiteral(S, AJD)   or
            ParseISO(S, AJD)         or
            ParseDMY(S, '/', AJD)    or
            ParseDMY(S, '.', AJD)    or
            ParseLongMonth(S, AJD);
end;

{ ============================================================
  Formatting
  ============================================================ }

function TJDEdit.FormatDate(AJD: Double): string;
var
  LY, LMo: Integer;
  LDay: Double;
  LFS: TFormatSettings;
begin
  if FShowAsJD then
  begin
    LFS := DefaultFormatSettings;
    LFS.DecimalSeparator := '.';
    Result := 'JD ' + FloatToStrF(AJD, ffFixed, 15, 1, LFS);
    Exit;
  end;

  if JDToCalendar(AJD, LY, LMo, LDay) then
    Result := Format('%.4d-%2.2d-%2.2d', [LY, LMo, Trunc(LDay)])
  else
    Result := Text;  // leave unchanged if conversion fails
end;

{ ============================================================
  Property accessors
  ============================================================ }

procedure TJDEdit.SetJulianDate(AValue: Double);
begin
  FJulianDate := AValue;
  FValid      := True;
  Text        := FormatDate(AValue);
end;

{ ============================================================
  Validation
  ============================================================ }

procedure TJDEdit.Validate;
var
  LJD: Double;
begin
  if ParseInput(Text, LJD) then
  begin
    FJulianDate      := LJD;
    FValid           := True;
    Color            := clWindow;
    Font.Color       := clWindowText;
    Hint             := '';
  end
  else
  begin
    FValid     := False;
    Color      := $CCCCFF;
    Font.Color := clRed;
    Hint       := 'Enter a date: YYYY-MM-DD, DD/MM/YYYY, "21 Jun 2025", or "JD 2460847.5"';
  end;
end;

procedure TJDEdit.Change;
begin
  inherited Change;
  Validate;
end;

procedure TJDEdit.DoExit;
begin
  inherited DoExit;
  if FValid then
    Text := FormatDate(FJulianDate);  // normalise display on exit
end;

{ ============================================================
  Constructor
  ============================================================ }

constructor TJDEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowAsJD   := False;
  FValid      := True;
  FJulianDate := CalendarToJD(2000, 1, 1.5);  // default: J2000.0
  Text        := FormatDate(FJulianDate);
  Hint        := 'Enter a date: YYYY-MM-DD, DD/MM/YYYY, "21 Jun 2025", or "JD 2460847.5"';
end;

end.
