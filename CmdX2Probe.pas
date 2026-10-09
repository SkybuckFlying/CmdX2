unit CmdX2Probe;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, CmdX2Types, CmdX2Env
  {$IFDEF WINDOWS}
  , Windows
  {$ENDIF}
  ;

function PerformCeilingProbe(var ASession: TSession; AForce: Boolean = False): Int64;

implementation

{$IFDEF WINDOWS}
function TestLaunchWithBlockSize(SizeInBytes: Int64; var ASession: TSession): Boolean;
var
  FillerName, FillerVal: string;
  FillerChars: Int64;
  TestEnv: TEnvironmentMap;
  BlockPtr: Pointer;
  BlockSize: Int64;
  SI: TStartupInfoW;
  PI: TProcessInformation;
  CmdLine: string;
  Res: Boolean;
begin
  Result := False;
  TestEnv := TEnvironmentMap.Create;
  try
    TestEnv.AddOrSetValue('SystemRoot', SysUtils.GetEnvironmentVariable('SystemRoot'));
    TestEnv.AddOrSetValue('SystemDrive', SysUtils.GetEnvironmentVariable('SystemDrive'));
    TestEnv.AddOrSetValue('TEMP', SysUtils.GetEnvironmentVariable('TEMP'));
    TestEnv.AddOrSetValue('TMP', SysUtils.GetEnvironmentVariable('TMP'));
    TestEnv.AddOrSetValue('PATH', 'C:\Windows\System32');

    FillerName := 'CMDX2_PROBE_FILLER';
    FillerChars := (SizeInBytes div SizeOf(Char)) - 200;
    if FillerChars < 0 then
      FillerChars := 0;

    FillerVal := StringOfChar('A', FillerChars);
    TestEnv.AddOrSetValue(FillerName, FillerVal);

    BlockPtr := BuildEnvironmentBlockUTF16(TestEnv, BlockSize);
    try
      FillChar(SI, SizeOf(SI), 0);
      SI.cb := SizeOf(SI);
      FillChar(PI, SizeOf(PI), 0);

      CmdLine := 'cmd.exe /c exit 0';
      Res := CreateProcessW(
        nil,
        PWideChar(CmdLine),
        nil,
        nil,
        False,
        CREATE_UNICODE_ENVIRONMENT or CREATE_NO_WINDOW,
        BlockPtr,
        nil,
        SI,
        PI
      );

      if Res then
      begin
        Result := True;
        CloseHandle(PI.hProcess);
        CloseHandle(PI.hThread);
      end;
    finally
      FreeEnvironmentBlockUTF16(BlockPtr);
    end;
  finally
    TestEnv.Free;
  end;
end;
{$ENDIF}

function PerformCeilingProbe(var ASession: TSession; AForce: Boolean = False): Int64;
const
  SAFETY_BOUND = 64 * 1024 * 1024; // 64 MB
{$IFDEF WINDOWS}
var
  LowSize, HighSize, MidSize, BestSize: Int64;
{$ENDIF}
begin
  if (not AForce) and (ASession.Config.ProbeConfig.CachedCeiling > 0) then
  begin
    ASession.Limits.MeasuredCeiling := ASession.Config.ProbeConfig.CachedCeiling;
    ASession.Limits.ProbeSucceeded := True;
    Exit(ASession.Limits.MeasuredCeiling);
  end;

  {$IFNDEF WINDOWS}
  ASession.Limits.MeasuredCeiling := 2 * 1024 * 1024; // 2MB default
  ASession.Limits.ProbeSucceeded := True;
  ASession.Limits.CachedAt := Now;
  ASession.Config.ProbeConfig.CachedCeiling := ASession.Limits.MeasuredCeiling;
  Exit(ASession.Limits.MeasuredCeiling);
  {$ELSE}

  if not TestLaunchWithBlockSize(1024, ASession) then
  begin
    ASession.Limits.MeasuredCeiling := 65534;
    ASession.Limits.ProbeSucceeded := False;
    Exit(65534);
  end;

  LowSize := 1024;
  HighSize := 2048;
  BestSize := LowSize;

  while HighSize <= SAFETY_BOUND do
  begin
    if TestLaunchWithBlockSize(HighSize, ASession) then
    begin
      LowSize := HighSize;
      BestSize := HighSize;
      HighSize := HighSize * 2;
    end
    else
      Break;
  end;

  if HighSize > SAFETY_BOUND then
    HighSize := SAFETY_BOUND;

  while (HighSize - LowSize) > 1024 do
  begin
    MidSize := (LowSize + HighSize) div 2;
    if TestLaunchWithBlockSize(MidSize, ASession) then
    begin
      LowSize := MidSize;
      BestSize := MidSize;
    end
    else
      HighSize := MidSize;
  end;

  ASession.Limits.MeasuredCeiling := BestSize;
  ASession.Limits.ProbeSucceeded := True;
  ASession.Limits.CachedAt := Now;
  ASession.Config.ProbeConfig.CachedCeiling := BestSize;
  Result := BestSize;
  {$ENDIF}
end;

end.
