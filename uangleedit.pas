unit UAngleEdit;

{
  Unit UAngleEdit

  Provides TAngleEdit, a TEdit descendant that accepts angles in a wide
  variety of textual formats, validates them, and reformats the display
  on exit.

  Supported input formats
  -----------------------
  Decimal degrees       -23.5           plain number, sign optional
  Degrees only          23°  23d        degree symbol or letter 'd'
  Degrees+Minutes       23°30'          also 23d30m or 23:30
  DMS                   23°30'00"       also 23d30m00s or 23:30:00
  Minutes only          30'             also 30m
  Minutes+Seconds       30'00"          also 30m00s
  Seconds only          45"             also 45s
  Hemisphere suffix     23°30'00" S     N/S for latitude, E/W for longitude

  The hemisphere suffix overrides the sign of the parsed value, so
  "23°30'00" S" is stored internally as -23.5°.

  Validation
  ----------
  The field background turns light-red whenever the input cannot be parsed
  or falls outside the configured range.  The Hint property is set to an
  explanatory message.  IsValid reflects the current state and is updated
  on every keystroke via the Change override.

  Display reformatting
  --------------------
  When focus leaves the field (Tab or clicking elsewhere), the raw input
  is replaced by a canonical form determined by AngleFormat:

    afDegrees   FloatToStr of the decimal degree value
    afDMS       DD° MM' SS.ss"   delegates to TAngle.ToDMS
                  With arNeg90_90 / arNeg180_180: |value| + N/S or E/W suffix
    afHMS       HHh MMm SS.ss s  hours-minutes-seconds

  Range modes
  -----------
  arNone        No range check
  ar0_360       Azimuth / bearing:  0 ≤ value ≤ 360
  arNeg90_90    Latitude:          -90 ≤ value ≤ 90
  arNeg180_180  Longitude:        -180 ≤ value ≤ 180

  Typical usage
  -------------
    AngleEdit1.AngleFormat := afDMS;
    AngleEdit1.RangeMode   := arNeg90_90;         // latitude field
    AngleEdit1.Degrees     := -23.5;

    // Read back as decimal degrees:
    LatDegrees := AngleEdit1.Degrees;

    // Or as the embedded TAngle record:
    A := AngleEdit1.Angle;
}

{$mode ObjFPC}{$H+}
{$MODESWITCH ADVANCEDRECORDS}

interface

uses
  Classes, SysUtils, StdCtrls, Graphics, RegExpr, Math, StrUtils;

type
  { TAngle — minimal embedded version.
    Identical in shape and behaviour to the TAngle in a_angle.pas for the
    methods used by this unit (Degrees field + ToDMS).  Kept as a record
    with a single Double field so it remains layout-compatible with the
    library type. }
  TAngle = record
    Degrees: Double;
    function ToDMS: string;
  end;

  { TAngleFormat — controls how the value is displayed after editing }
  TAngleFormat = (
    afDegrees,  // plain decimal degrees,      e.g.  -23.5
    afDMS,      // degrees-minutes-seconds,    e.g.  23° 30' 0.00" S
    afHMS       // hours-minutes-seconds,      e.g.  1h 34m 0.00s
  );

  { TAngleRange — optional range constraint applied during validation }
  TAngleRange = (
    arNone,        // no constraint
    ar0_360,       // 0 to 360  (azimuth, bearing)
    arNeg90_90,    // -90 to 90  (geographic latitude)
    arNeg180_180   // -180 to 180  (geographic longitude)
  );

  { TAngleEdit
    A TEdit descendant that parses, validates, and formats angular values.

    Set AngleFormat and RangeMode before use.
    Read/write the angle via the Degrees property (Double) or the Angle
    property (TAngle record). }
  TAngleEdit = class(TEdit)
  private
    FAngleFormat: TAngleFormat;
    FRange:       TAngleRange;
    FValid:       Boolean;

    function ParseAngle(const Input: string; out Value: Double): Boolean;
    function ExtractHemisphere(var S: string; out Sign: Double): Boolean;
    function CheckRange(Value: Double; out Msg: string): Boolean;

    function  GetDegrees: Double;
    procedure SetDegrees(const AValue: Double);

    function FormatDMS(Value: Double): string;
    function FormatDMSDirectional(Value: Double): string;
    function FormatHMS(Value: Double): string;

    procedure Validate;

  protected
    procedure Change; override;
    procedure DoExit; override;

  public
    constructor Create(AOwner: TComponent); override;

    function  GetAngleRecord: TAngle;
    procedure SetAngleRecord(const AValue: TAngle);

    property Angle: TAngle read GetAngleRecord write SetAngleRecord;
    property IsValid: Boolean read FValid;

    function AsRadians: Double;

  published
    property Degrees: Double
      read  GetDegrees
      write SetDegrees;

    property AngleFormat: TAngleFormat
      read  FAngleFormat
      write FAngleFormat
      default afDegrees;

    property RangeMode: TAngleRange
      read  FRange
      write FRange
      default arNone;
  end;

implementation

{ ============================================================
  TAngle — embedded minimal implementation
  ============================================================
  Reproduces the exact output of the original a_angle.TAngle.ToDMS so
  TAngleEdit's formatted display is byte-identical to what it produced
  when coupled to the astro library. }

function TAngle.ToDMS: string;
var
  LAbsDeg:    Double;
  LDeg, LMin: Integer;
  LSec:       Double;
  LSign:      string;
begin
  LAbsDeg := System.Abs(Degrees);
  LSign   := IfThen(Degrees < 0, '-', '');
  LDeg    := Trunc(LAbsDeg);
  LMin    := Trunc((LAbsDeg - LDeg) * 60);
  LSec    := ((LAbsDeg - LDeg) * 60 - LMin) * 60;
  Result  := Format('%s%d° %d'' %.2f"', [LSign, LDeg, LMin, LSec]);
end;

{ ============================================================
  Hemisphere extraction
  ============================================================ }

function TAngleEdit.ExtractHemisphere(var S: string; out Sign: Double): Boolean;
var
  R: TRegExpr;
  H: string;
begin
  Result := False;
  Sign   := 1;

  R := TRegExpr.Create('\b([NWSEnwse])\s*$');
  try
    if R.Exec(S) then
    begin
      H := UpperCase(R.Match[1]);

      if (H = 'S') or (H = 'W') then Sign := -1
                                  else Sign :=  1;

      S      := Trim(R.Replace(S, ''));
      Result := True;
    end;
  finally
    R.Free;
  end;
end;

{ ============================================================
  Angle parser
  ============================================================ }

function TAngleEdit.ParseAngle(const Input: string; out Value: Double): Boolean;
var
  S:        string;
  R:        TRegExpr;
  d, m, s2: Double;
  hemiSign: Double;
  fs:       TFormatSettings;
begin
  Result := False;
  Value  := 0;

  fs                  := DefaultFormatSettings;
  fs.DecimalSeparator := '.';

  S := Trim(Input);
  S := StringReplace(S, ',', '.', [rfReplaceAll]);

  ExtractHemisphere(S, hemiSign);

  { --- Decimal degrees ------------------------------------------------- }
  if TryStrToFloat(S, Value, fs) then
  begin
    Value := Value * hemiSign;
    Exit(True);
  end;

  { --- DMS: 12°34'56.78"  /  12d34m56s  /  12:34:56 ------------------- }
  R := TRegExpr.Create(
    '^\s*(-?\d+)[°d\s:]+\s*(\d+)[''m\s:]+\s*(\d+(?:\.\d+)?)(?:"|s|\s|$)');
  try
    if R.Exec(S) then
    begin
      d     := StrToFloatDef(R.Match[1], 0, fs);
      m     := StrToFloatDef(R.Match[2], 0, fs);
      s2    := StrToFloatDef(R.Match[3], 0, fs);
      Value := Math.Sign(d) * (Abs(d) + m / 60 + s2 / 3600) * hemiSign;
      Exit(True);
    end;
  finally
    R.Free;
  end;

  { --- DM: 12°34.5'  /  12d34m ---------------------------------------- }
  R := TRegExpr.Create(
    '^\s*(-?\d+)[°d\s:]+\s*(\d+(?:\.\d+)?)[''m\s]?$');
  try
    if R.Exec(S) then
    begin
      d     := StrToFloatDef(R.Match[1], 0, fs);
      m     := StrToFloatDef(R.Match[2], 0, fs);
      Value := Math.Sign(d) * (Abs(d) + m / 60) * hemiSign;
      Exit(True);
    end;
  finally
    R.Free;
  end;

  { --- D: 12°  /  12d ------------------------------------------------- }
  R := TRegExpr.Create('^\s*(-?\d+(?:\.\d+)?)[°d]\s*$');
  try
    if R.Exec(S) then
    begin
      d     := StrToFloatDef(R.Match[1], 0, fs);
      Value := d * hemiSign;
      Exit(True);
    end;
  finally
    R.Free;
  end;

  { --- MS: 34'56.78"  /  34m56s --------------------------------------- }
  R := TRegExpr.Create(
    '^\s*(\d+)\s*[''m]\s*(\d+(?:\.\d+)?)\s*["s]\s*$');
  try
    if R.Exec(S) then
    begin
      m     := StrToFloatDef(R.Match[1], 0, fs);
      s2    := StrToFloatDef(R.Match[2], 0, fs);
      Value := (m / 60 + s2 / 3600) * hemiSign;
      Exit(True);
    end;
  finally
    R.Free;
  end;

  { --- M: 34'  /  34m ------------------------------------------------- }
  R := TRegExpr.Create('^\s*(-?\d+(?:\.\d+)?)[''m]\s*$');
  try
    if R.Exec(S) then
    begin
      m     := StrToFloatDef(R.Match[1], 0, fs);
      Value := (m / 60) * hemiSign;
      Exit(True);
    end;
  finally
    R.Free;
  end;

  { --- S: 56.78"  /  56s ---------------------------------------------- }
  R := TRegExpr.Create(
    '^\s*(-?(?:\d+(?:\.\d*)?|\.\d+))["s]\s*$');
  try
    if R.Exec(S) then
    begin
      s2    := StrToFloatDef(R.Match[1], 0, fs);
      Value := (s2 / 3600) * hemiSign;
      Exit(True);
    end;
  finally
    R.Free;
  end;
end;

{ ============================================================
  Formatting
  ============================================================ }

function TAngleEdit.FormatDMS(Value: Double): string;
var
  A: TAngle;
begin
  A.Degrees := Value;
  Result    := A.ToDMS;
end;

function TAngleEdit.FormatDMSDirectional(Value: Double): string;
var
  A:   TAngle;
  Dir: string;
begin
  case FRange of
    arNeg90_90:   Dir := IfThen(Value >= 0, 'N', 'S');
    arNeg180_180: Dir := IfThen(Value >= 0, 'E', 'W');
  else            Dir := '';
  end;

  A.Degrees := Abs(Value);
  Result    := A.ToDMS;

  if Dir <> '' then
    Result := Result + ' ' + Dir;
end;

function TAngleEdit.FormatHMS(Value: Double): string;
var
  h:     Integer;
  m:     Integer;
  s:     Double;
  sign:  string;
  total: Double;
begin
  if Value < 0 then
  begin
    sign  := '-';
    Value := Abs(Value);
  end
  else
    sign := '';

  total := Value / 15;
  h     := Trunc(total);
  m     := Trunc(Frac(total) * 60);
  s     := (Frac(total) * 60 - m) * 60;

  Result := Format('%s%dh %dm %.2fs', [sign, h, m, s]);
end;

{ ============================================================
  Property accessors
  ============================================================ }

function TAngleEdit.GetDegrees: Double;
begin
  if not ParseAngle(Text, Result) then
    Result := 0;
end;

procedure TAngleEdit.SetDegrees(const AValue: Double);
begin
  case FAngleFormat of
    afDegrees:
      Text := FloatToStr(AValue);

    afDMS:
      if FRange in [arNeg90_90, arNeg180_180] then
        Text := FormatDMSDirectional(AValue)
      else
        Text := FormatDMS(AValue);

    afHMS:
      Text := FormatHMS(AValue);
  end;
end;

function TAngleEdit.AsRadians: Double;
begin
  Result := Degrees * Pi / 180;
end;

{ ============================================================
  Validation
  ============================================================ }

function TAngleEdit.CheckRange(Value: Double; out Msg: string): Boolean;
begin
  Result := True;
  Msg    := '';

  case FRange of
    arNeg90_90:
      if (Value < -90) or (Value > 90) then
      begin
        Msg    := 'Latitude must be between -90° and 90°';
        Result := False;
      end;

    arNeg180_180:
      if (Value < -180) or (Value > 180) then
      begin
        Msg    := 'Longitude must be between -180° and 180°';
        Result := False;
      end;

    ar0_360:
      if (Value < 0) or (Value > 360) then
      begin
        Msg    := 'Angle must be between 0° and 360°';
        Result := False;
      end;
  end;
end;

procedure TAngleEdit.Validate;
var
  V:   Double;
  Msg: string;
begin
  if not ParseAngle(Text, V) then
  begin
    FValid     := False;
    Color      := $CCCCFF;
    Font.Color := clRed;
    Hint       := 'Invalid angle format';
    Exit;
  end;

  if not CheckRange(V, Msg) then
  begin
    FValid     := False;
    Color      := $CCCCFF;
    Font.Color := clRed;
    Hint       := Msg;
    Exit;
  end;

  FValid     := True;
  Color      := clWindow;
  Font.Color := clWindowText;
  Hint       := '';
end;

{ ============================================================
  Protected overrides
  ============================================================ }

procedure TAngleEdit.Change;
begin
  inherited Change;
  Validate;
end;

procedure TAngleEdit.DoExit;
begin
  inherited DoExit;
  if FValid then
    SetDegrees(GetDegrees);
end;

{ ============================================================
  Constructor
  ============================================================ }

constructor TAngleEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAngleFormat := afDegrees;
  FRange       := arNone;
  FValid       := True;
end;

{ ============================================================
  TAngle record bridge
  ============================================================ }

function TAngleEdit.GetAngleRecord: TAngle;
begin
  Result.Degrees := Self.Degrees;
end;

procedure TAngleEdit.SetAngleRecord(const AValue: TAngle);
begin
  Self.Degrees := AValue.Degrees;
end;

end.
