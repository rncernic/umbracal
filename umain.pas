unit UMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, StdCtrls,
  ComCtrls, ExtCtrls, EditBtn, Spin, Buttons, StrUtils,
  ShellCtrls, SpinEx, UJDEdit,
  UAboutBox,
  UUmbracal,
  UAngle, UAngleEdit,
  UHelper, UHours,
  UTime;

type
  { TfrmMain }
  TfrmMain = class(TForm)
    btnLoad: TButton;
    aedtLatitude: TAngleEdit;
    aedtLongitude: TAngleEdit;
    btnSave: TButton;
    btnNow: TButton;
    chkDST: TCheckBox;
    grpEphemeris: TGroupBox;
    grpDialist: TGroupBox;
    grpRiseSet: TGroupBox;
    grpDateTime: TGroupBox;
    grpLocation: TGroupBox;
    jdedtDate: TJDEdit;
    edtElevation: TEdit;
    edtName: TEdit;
    lblGMST: TLabel;
    lblSunLongitude: TLabel;
    lblLHA: TLabel;
    lblSemiDiameter: TLabel;
    lblRadiusVector: TLabel;
    lblDeclination: TLabel;
    lblAzimuthAstro: TLabel;
    lblAzimuthNav: TLabel;
    lblRightAscension: TLabel;
    lblAltitude: TLabel;
    lblGHAvernal: TLabel;
    lblGHAsun: TLabel;
    lblDayLength: TLabel;
    lblDialistBabilonian: TLabel;
    lblDialistEoT: TLabel;
    lblDialistItalian: TLabel;
    lblDialistLongCorrection: TLabel;
    lblDialistLT: TLabel;
    lblDialistShadow: TLabel;
    lblDialistSidereal: TLabel;
    lblDialistSpeed: TLabel;
    lblDialistSundial: TLabel;
    lblDialistSundialTime: TLabel;
    lblDialistTemporal: TLabel;
    lblDialistTotalCorrection: TLabel;
    lblDialistUT: TLabel;
    lblRise: TLabel;
    lblRiseAstroTw: TLabel;
    lblRiseCivTw: TLabel;
    lblRiseNauTw: TLabel;
    lblSet: TLabel;
    lblSetAstroTw: TLabel;
    lblSetCivTw: TLabel;
    lblSetNauTw: TLabel;
    lblTransit: TLabel;
    pnlOutput: TPanel;
    pnlInput: TPanel;
    spbAbout: TSpeedButton;
    speTimeZone: TFloatSpinEdit;
    lblName: TLabel;
    lblDate: TLabel;
    lblTime: TLabel;
    lblLST: TLabel;
    lblLatitude: TLabel;
    lblTimeZone: TLabel;
    lblDoW: TLabel;
    lblJD: TLabel;
    lblDeltaT: TLabel;
    lblLongitude: TLabel;
    lblElevation: TLabel;
    stAStroTwRise: TStaticText;
    stAstroTwSet: TStaticText;
    stBabilonian: TStaticText;
    stCivilianTwRise: TStaticText;
    stCivilianTwSet: TStaticText;
    stDayLength: TStaticText;
    stDoW: TStaticText;
    stEoT: TStaticText;
    stItalian: TStaticText;
    stLocalTime: TStaticText;
    stGMST: TStaticText;
    stSunAzimuthAstro: TStaticText;
    stSunAzimuthNav: TStaticText;
    stSunRightAscensionDeg: TStaticText;
    stSunLongitude: TStaticText;
    stLongitudeCorrection: TStaticText;
    stLST: TStaticText;
    stNauticalTwRise: TStaticText;
    stNauticalTwSet: TStaticText;
    stRise: TStaticText;
    stSet: TStaticText;
    stShadow: TStaticText;
    stSidereal: TStaticText;
    stSpeed: TStaticText;
    stSundialTime: TStaticText;
    stSunDeclination: TStaticText;
    stSunRadiusVector: TStaticText;
    stSunGHAVernal: TStaticText;
    stSunGHASun: TStaticText;
    stSunLHASun: TStaticText;
    stSunRightAscensionHMS: TStaticText;
    stSunSemiDiameter: TStaticText;
    stSunAltitude: TStaticText;
    stTemporal: TStaticText;
    stTotalCorrection: TStaticText;
    stTransit: TStaticText;
    stUT: TStaticText;
    stJD: TStaticText;
    stDeltaT: TStaticText;
    tmeTime: TTimeEdit;

    procedure btnNowClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure spbAboutClick(Sender: TObject);
  private
    function BuildObserver: TObserver;
    function CurrentJulianDate: Double;
    function FormatHoursMM(ADecimalHours: Double): string;
    function CivilOffsetHours: Double;      // local clock -> UT, DST included
    function StandardOffsetHours: Double;   // legal meridian, DST excluded

    procedure UpdateOutputs;
    procedure UpdateRiseSet(const ARiseSet: TRiseSet);

    procedure LocationChangeHandler(Sender: TObject);

    function ConfigFileName: String;
    procedure LoadSettings;
    Procedure SaveSettings;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.lfm}

uses
  IniFiles;

{ ============================================================
  Form initialisation
  ============================================================ }

procedure TfrmMain.FormCreate(Sender: TObject);
begin

  frmMain.Caption:= APPLICATION_NAME + ' v. ' + VERSION_HISTORY[0].Version +
  ' (' + VERSION_HISTORY[0].Date  + ')';

  { --- Latitude field --- }
  aedtLatitude := TAngleEdit.Create(Self);
  aedtLatitude.Parent      := grpLocation;
  aedtLatitude.Left        := 72;
  aedtLatitude.Top         := 40;
  aedtLatitude.Width       := 104;
  aedtLatitude.AngleFormat := afDMS;        // exit reformats as DD° MM' SS" N/S
  aedtLatitude.RangeMode   := arNeg90_90;
  aedtLatitude.Text        := '0';
  aedtLatitude.ShowHint    := True;

  { --- Longitude field --- }
  aedtLongitude := TAngleEdit.Create(Self);
  aedtLongitude.Parent      := grpLocation;
  aedtLongitude.Left        := 72;
  aedtLongitude.Top         := 72;
  aedtLongitude.Width       := 104;
  aedtLongitude.AngleFormat := afDMS;        // exit reformats as DD° MM' SS" E/W
  aedtLongitude.RangeMode   := arNeg180_180;
  aedtLongitude.Text        := '0';

  { --- Name filed --- }
  edtName.Text := 'My observatory';

  { --- Date field --- }
  jdedtDate := TJDEdit.Create(Self);
  jdedtDate.Parent     := grpDateTime;
  jdedtDate.Left       := 72;
  jdedtDate.Top        := 10;
  jdedtDate.Width      := 110;
  jdedtDate.TabOrder   := 6;
  jdedtDate.JulianDate := Now + 2415018.5;
  jdedtDate.OnExit := @LocationChangeHandler;

  { --- Time field --- }
  tmeTime.Time := Frac(Now);

  { --- Tab Order --- }
  edtName.TabOrder       := 0;
  aedtLatitude.TabOrder  := 1;
  aedtLongitude.TabOrder := 2;
  edtElevation.TabOrder  := 3;
  speTimeZone.TabOrder   := 4;
  chkDST.TabOrder        := 5;
  jdedtDate.TabOrder     := 6;
  tmeTime.TabOrder       := 7;
  btnNow.TabOrder        := 8;
  btnLoad.TabOrder       := 9;
  btnSave.TabOrder       := 10;

  { Wire OnChange after fields are ready to avoid premature firing }
  aedtLatitude.OnChange      := @LocationChangeHandler;
  aedtLongitude.OnChange     := @LocationChangeHandler;
  aedtLatitude.OnEditingDone := @LocationChangeHandler;

  tmeTime.OnChange           := @LocationChangeHandler;

  chkDST.OnChange            := @LocationChangeHandler;
  speTimeZone.OnChange       := @LocationChangeHandler;

  { Load settings }
  LoadSettings;

  { Initial calculation }
  UpdateOutputs;
end;

// --- Persistência ---
// function GetAppConfigFile(Global: Boolean; SubDir: Boolean = False): string;
//
//  Global: Set to False for a specific user's folder (recommended). Set to True
//  for a system-wide folder (requires admin/root privileges to write).
//
//  SubDir: Set to True to organize files inside an extra nested application
//  subdirectory.
//
//  Global = False (Per User Path)
//  Windows -> C:\Users\<User>\AppData\Local\<AppName>\<AppName>.cfg
//  Linux   -> ~/.config/<AppName>.cfg
//  MacOS   -> ~/Library/Application Support/<AppName>.cfg
//
//  Global = True (System-Wide Path)
//  Windows -> C:\ProgramData\<AppName>\<AppName>.cfg
//  Linux   -> /etc/<AppName>.cfg
//  MacOS   -> /Library/Application Support/<AppName>.cfg
//
//  Application Name: By default, <AppName> matches the executable name. You can
//  override this behavior globally by assigning a custom method to the
//  OnGetApplicationName callback.Application Name: By default, <AppName>
//  matches the executable name. You can override this behavior globally by
//  assigning a custom method to the OnGetApplicationName callback.
//
//  File Extension: The function defaults to the .cfg extension. To change it,
//  modify the ConfigExtension global variable before calling the function.
//
function TfrmMain.ConfigFileName: string;
begin
  Result := GetAppConfigFile(False);
  ForceDirectories(ExtractFilePath(Result));
end;

procedure TfrmMain.LoadSettings;
var ini: TIniFile;
begin
  ini := TIniFile.Create(ConfigFileName);
  try
    edtName.Text         := ini.ReadString('data', 'name', 'MyPlace');
    aedtLatitude.Text    := ini.ReadString('data', 'latitude', '');
    aedtLongitude.Text   := ini.ReadString('data', 'longitude', '');
    edtElevation.Text    := ini.ReadString('data', 'elevation', '');
    speTimeZone.Text     := ini.ReadString('data', 'timezone', '');
    //chkDST.State         := ini.ReadString('paths', 'dst', '');
    jdedtDate.JulianDate := StrToFloat(ini.ReadString('data', 'date', '0'));
  finally
    ini.Free;
  end;
end;

procedure TfrmMain.SaveSettings;
var ini: TIniFile;
begin
  ini := TIniFile.Create(ConfigFileName);
  try
    ini.WriteString('data', 'name', edtName.Text);
    ini.WriteString('data', 'latitude', aedtLatitude.Text);
    ini.WriteString('data', 'longitude', aedtLongitude.Text);
    ini.WriteString('data', 'elevation', edtElevation.Text);
    ini.WriteString('data', 'timezone', speTimeZone.Text);
    //ini.WriteString('data', 'dst', chkDST.State);
    ini.WriteString('data', 'date', FloatToStr(jdedtDate.JulianDate));
    ini.UpdateFile;
  finally
    ini.Free;
  end;
end;

{ ============================================================
  Event handlers
  ============================================================ }

procedure TfrmMain.btnNowClick(Sender: TObject);
var
  LNow: TDateTime;
begin
  LNow := Now;
  { Set the date (JD). TJDEdit.JulianDate expects a JD value. }
  jdedtDate.JulianDate := Trunc(LNow) + 2415018.5;

  { Set the time — assign just the fractional (time) part of Now. }
  tmeTime.Time := Frac(LNow);

  { OnChange on tmeTime will fire UpdateOutputs, but call it explicitly in
    case the assignment doesn't trigger the event when the value is identical. }
  UpdateOutputs;
end;

procedure TfrmMain.btnLoadClick(Sender: TObject);
begin
  { Called after loading a configuration file — re-read the fields and recalculate }
  UpdateOutputs;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  SaveSettings;
end;

procedure TfrmMain.spbAboutClick(Sender: TObject);
begin
  ShowAboutBox;
end;

procedure TfrmMain.LocationChangeHandler(Sender: TObject);
begin
  { Recalculate whenever either coordinate field changes }
  UpdateOutputs;
end;

{ ============================================================
  Private helpers
  ============================================================ }

{ Build a TObserver from the current UI state }
function TfrmMain.BuildObserver: TObserver;
begin
  Result.Latitude.Degrees  := aedtLatitude.Degrees;
  Result.Longitude.Degrees := aedtLongitude.Degrees;
  Result.Elevation := StrToFloatDef(edtElevation.Text, 0);
end;

function TfrmMain.CurrentJulianDate: Double;
begin
  Result := jdedtDate.JulianDate + Frac(tmeTime.Time)
            - CivilOffsetHours / 24.0;
end;

{ Convert decimal hours (e.g. 14.5) to "HH:MM" }
function TfrmMain.FormatHoursMM(ADecimalHours: Double): string;
var
  LH, LM, LSign: Integer;
begin
  LSign := 1;
  ADecimalHours := NormalizeHours(ADecimalHours + CivilOffsetHours);
  if ADecimalHours < 0 then
  begin
    LSign := -1;
    ADecimalHours := Abs(ADecimalHours);
  end;
  LH := Trunc(ADecimalHours);
  LM := Round((ADecimalHours - LH) * 60.0);
  if LM = 60 then begin LM := 0; Inc(LH); end;
  Result := Format('%.2d:%.2d', [LH * LSign, LM]);
end;

{ What the user's clock reads ahead of UT. Input date and time are always
  local, so this is the only conversion into UT. }
function TfrmMain.CivilOffsetHours: Double;
begin
  Result := speTimeZone.Value;
  if chkDST.Checked then
    Result := Result + 1.0;
end;

{ The meridian the zone is legally referred to. DST shifts clocks, not
  meridians, so it must not appear here. }
function TfrmMain.StandardOffsetHours: Double;
begin
  Result := speTimeZone.Value;
end;

{ ============================================================
  Core update
  ============================================================ }

procedure TfrmMain.UpdateOutputs;
var
  LEngine: TSunEngine;
  LRS:     TRiseSet;
  LNowUT:  Double;
  LHours:  THourSystems;
begin
  LEngine := TSunEngine.Create(BuildObserver, CurrentJulianDate,
                             CivilOffsetHours,
                             StandardOffsetHours);
  try
    LRS := LEngine.RiseSet;
    // --- Rise & Set ---
    UpdateRiseSet(LRS);

    // --- Date&Time ---
    stJD.Caption := JDToStrFull(CurrentJulianDate);

    LNowUT := NormalizeHours(Frac(CurrentJulianDate + 0.5) * 24.0);
    LHours := ComputeHourSystems(LNowUT,
                                 LRS.Sunrise.Rise,
                                 LRS.Sunrise.SetTime,
                                 LRS.Sunrise.TwilightType = 'Normal');
    stDoW.Caption    := DayOfWeekName(LEngine.Data.DayOfWeek);
    stGMST.Caption   := HourCountToStr(LEngine.Data.GMSTDeg / 15.0);
    stLST.Caption    := HourCountToStr(LEngine.Data.LSTDeg / 15.0);
    stDeltaT.Caption := Format('%.2f', [LEngine.Data.DeltaTSec]);

    // --- Ephemeris ---
    stSunLongitude.Caption         := DegToDMS(LEngine.Data.SunLongitudeDeg, asSigned, 0);
    stSunDeclination.Caption       := DegToDMS(LEngine.Data.Equatorial.DeclinationDeg, asSigned, 0);
    stSunRightAscensionDeg.Caption := DegToDMS(LEngine.Data.Equatorial.RightAscensionDeg, asSigned, 0);
    stSunRightAscensionHMS.Caption := HourCountToStr(LEngine.Data.Equatorial.RightAscensionDeg / 15.0);
    stSunGHAVernal.Caption         := DegToDMS(LEngine.Data.GHAVernalDeg, asSigned, 0);
    stSunGHASun.Caption            := DegToDMS(LEngine.Data.GHASunDeg, asSigned, 0);
    stSunLHASun.Caption            := DegToDMS(LEngine.Data.LHASunDeg, asSigned, 0);

    stSunRadiusVector.Caption      := Format('%.6f', [LEngine.Data.RadiusVectorAU]);
    stSunAzimuthAstro.Caption      := DegToDMS(LEngine.Data.Horizontal.AzimuthAstro, asSigned, 0);
    stSunAzimuthNav.Caption        := DegToDMS(LEngine.Data.Horizontal.AzimuthNav, asSigned, 0);;
    stSunAltitude.Caption          := DegToDMS(LEngine.Data.Horizontal.Altitude, asSigned, 0);
    stSunSemiDiameter.Caption      := Format('%.2f', [LEngine.Data.SemiDiameterDeg * 60]);

    // --- Dialist ---
    stLocalTime.Caption            := HourCountToStr(Frac(tmeTime.Time) * 24.0);
    stEoT.Caption                  := HourCountToStr(LEngine.Data.EoTMinutes);
    stLongitudeCorrection.Caption  := HourCountToStr(LEngine.Data.LongitudeCorrMin);
    stTotalCorrection.Caption      := HourCountToStr(LEngine.Data.TotalCorrMin);
    stSundialTime.Caption          := HourCountToStr(LEngine.Data.SundialHours);
    stSpeed.Caption                := IfThen(LEngine.Data.EoTMinutes < 0, 'Slower', 'Faster');

    stUT.Caption                   := HourCountToStr(LEngine.Data.UTHours);
    // Sideral hours are equal to Vernal GHA
    stSidereal.Caption             := HourCountToStr(LEngine.Data.GHAVernalDeg / 15.0);
    stShadow.Caption               := Format('%.4f',[Lengine.Data.ShadowRatio]);

    if LHours.Valid then
    begin
      stItalian.Caption    := Format('%s', [HourCountToStr(LHours.Italian)]);
      stBabilonian.Caption := Format('%s', [HourCountToStr(LHours.Babylonian)]);
      if LHours.IsDaytime then
        stTemporal.Caption := Format('%s', [HourCountToStr(LHours.Temporal)])
      else
        stTemporal.Caption := Format('%s', [HourCountToStr(LHours.Nocturnal)]);
      stDayLength.Caption  := HourCountToStr(LHours.DayLength);
    end
    else
    begin
      stItalian.Caption    := LRS.Sunrise.TwilightType;
      stBabilonian.Caption := LRS.Sunrise.TwilightType;
      stTemporal.Caption   := LRS.Sunrise.TwilightType;
    end;
  finally
    LEngine.Free;
  end;
end;

procedure TfrmMain.UpdateRiseSet(const ARiseSet: TRiseSet);

  procedure SetTwilight(ARise, ASet: TStaticText; const ATw: TTwilight);
  begin
    if ATw.TwilightType = 'Normal' then
    begin
      ARise.Caption := FormatHoursMM(ATw.Rise);
      ASet.Caption  := FormatHoursMM(ATw.SetTime);
    end
    else
    begin
      ARise.Caption := ATw.TwilightType;  // 'PolarDay' or 'PolarNight'
      ASet.Caption  := ATw.TwilightType;
    end;
  end;

begin
  SetTwilight(stRise,            stSet,           ARiseSet.Sunrise);
  SetTwilight(stCivilianTwRise,  stCivilianTwSet, ARiseSet.Civil);
  SetTwilight(stNauticalTwRise,  stNauticalTwSet, ARiseSet.Nautical);
  SetTwilight(stAStroTwRise,     stAstroTwSet,    ARiseSet.Astronomical);

  if ARiseSet.Sunrise.TwilightType = 'Normal' then
    stTransit.Caption := FormatHoursMM(ARiseSet.Sunrise.Culmination)
  else
    stTransit.Caption := ARiseSet.Sunrise.TwilightType;
end;

end.
