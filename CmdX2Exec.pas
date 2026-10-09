unit CmdX2Exec;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, CmdX2Types, CmdX2Env, CmdX2Resolver, CmdX2Path, CmdX2Parser
  {$IFDEF WINDOWS}
  , Windows
  {$ELSE}
  , Process
  {$ENDIF}
  ;

function ExecuteParsedCommandLine(var ASession: TSession; ACmdLine: TParsedCommandLine): Integer;
function LaunchProcessDirect(var ASession: TSession; const AExePath: string; AArgs: TStringList;
  const ARedirInput, ARedirOutput, ARedirStderr: string; AAppendOutput: Boolean): Integer;

implementation

uses
  CmdX2Builtins;

{$IFDEF WINDOWS}
function LaunchProcessDirect(var ASession: TSession; const AExePath: string; AArgs: TStringList;
  const ARedirInput, ARedirOutput, ARedirStderr: string; AAppendOutput: Boolean): Integer;
var
  CmdLineStr: string;
  I: Integer;
  BlockPtr: Pointer;
  BlockSize: Int64;
  SI: TStartupInfoW;
  PI: TProcessInformation;
  SecAttr: TSecurityAttributes;
  HIn, HOut, HErr: THandle;
  Res: Boolean;
  ExitCode: DWORD;
begin
  Result := 9009;
  HIn := INVALID_HANDLE_VALUE;
  HOut := INVALID_HANDLE_VALUE;
  HErr := INVALID_HANDLE_VALUE;

  CmdLineStr := '"' + AExePath + '"';
  if Assigned(AArgs) then
  begin
    for I := 0 to AArgs.Count - 1 do
      CmdLineStr := CmdLineStr + ' ' + AArgs[I];
  end;

  BlockPtr := BuildEnvironmentBlockUTF16(ASession.Environment, BlockSize);
  try
    if (ASession.Limits.MeasuredCeiling > 0) and (BlockSize > ASession.Limits.MeasuredCeiling) then
    begin
      Writeln(ErrOutput, Format('The environment block for ''%s'' is %d bytes, which exceeds the measured ceiling of %d bytes on this system. PATH contributes %d bytes.',
             [ExtractFileName(AExePath), BlockSize, ASession.Limits.MeasuredCeiling, Length(ASession.RawPath) * SizeOf(Char)]));

      if ASession.Config.Strategy = esRefuseAndExplain then
      begin
        ASession.ErrorLevel := 9008;
        Exit(9008);
      end;
    end;

    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    SI.hStdOutput := GetStdHandle(STD_OUTPUT_HANDLE);
    SI.hStdError := GetStdHandle(STD_ERROR_HANDLE);

    FillChar(SecAttr, SizeOf(SecAttr), 0);
    SecAttr.nLength := SizeOf(SecAttr);
    SecAttr.bInheritHandle := True;

    if ARedirInput <> '' then
    begin
      HIn := CreateFileW(PWideChar(ARedirInput), GENERIC_READ, FILE_SHARE_READ, @SecAttr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
      if HIn <> INVALID_HANDLE_VALUE then
        SI.hStdInput := HIn;
    end;

    if ARedirOutput <> '' then
    begin
      if AAppendOutput then
        HOut := CreateFileW(PWideChar(ARedirOutput), FILE_APPEND_DATA, FILE_SHARE_READ or FILE_SHARE_WRITE, @SecAttr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0)
      else
        HOut := CreateFileW(PWideChar(ARedirOutput), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @SecAttr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);

      if HOut <> INVALID_HANDLE_VALUE then
        SI.hStdOutput := HOut;
    end;

    if ARedirStderr <> '' then
    begin
      HErr := CreateFileW(PWideChar(ARedirStderr), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @SecAttr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
      if HErr <> INVALID_HANDLE_VALUE then
        SI.hStdError := HErr;
    end;

    FillChar(PI, SizeOf(PI), 0);

    Res := CreateProcessW(
      nil,
      PWideChar(CmdLineStr),
      nil,
      nil,
      True,
      CREATE_UNICODE_ENVIRONMENT,
      BlockPtr,
      PWideChar(ASession.Cwd),
      SI,
      PI
    );

    if Res then
    begin
      WaitForSingleObject(PI.hProcess, INFINITE);
      GetExitCodeProcess(PI.hProcess, ExitCode);
      CloseHandle(PI.hProcess);
      CloseHandle(PI.hThread);
      Result := ExitCode;
    end;

  finally
    if HIn <> INVALID_HANDLE_VALUE then CloseHandle(HIn);
    if HOut <> INVALID_HANDLE_VALUE then CloseHandle(HOut);
    if HErr <> INVALID_HANDLE_VALUE then CloseHandle(HErr);
    FreeEnvironmentBlockUTF16(BlockPtr);
  end;

  ASession.ErrorLevel := Result;
end;

{$ELSE}

function LaunchProcessDirect(var ASession: TSession; const AExePath: string; AArgs: TStringList;
  const ARedirInput, ARedirOutput, ARedirStderr: string; AAppendOutput: Boolean): Integer;
var
  Proc: TProcess;
  I: Integer;
begin
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := AExePath;
    if Assigned(AArgs) then
    begin
      for I := 0 to AArgs.Count - 1 do
        Proc.Parameters.Add(AArgs[I]);
    end;
    Proc.Options := [poWaitOnExit];
    Proc.Execute;
    Result := Proc.ExitCode;
  finally
    Proc.Free;
  end;
  ASession.ErrorLevel := Result;
end;

{$ENDIF}

function ExecuteParsedCommandLine(var ASession: TSession; ACmdLine: TParsedCommandLine): Integer;
var
  I: Integer;
  Cmd: TParsedCommand;
  ResolvedFile, MatchedExt: string;
  PathIdx: Integer;
  ExecRes: Integer;
begin
  Result := 0;
  if not Assigned(ACmdLine) then
    Exit;

  for I := 0 to ACmdLine.Count - 1 do
  begin
    Cmd := ACmdLine[I];
    if Cmd.ProgramName = '' then
      Continue;

    if IsBuiltInCommand(Cmd.ProgramName) then
    begin
      ExecRes := ExecuteBuiltinCommand(ASession, Cmd.ProgramName, Cmd.Args);
    end;

    if (not IsBuiltInCommand(Cmd.ProgramName)) or (ExecRes <> 0) then
    begin
      if ResolveCommand(ASession, Cmd.ProgramName, ResolvedFile, MatchedExt, PathIdx) then
      begin
        ExecRes := LaunchProcessDirect(ASession, ResolvedFile, Cmd.Args, Cmd.RedirInput, Cmd.RedirOutput, Cmd.RedirStderr, Cmd.RedirAppend);
      end
      else if not IsBuiltInCommand(Cmd.ProgramName) then
      begin
        Writeln(ErrOutput, Format('''%s'' is not recognized as an internal or external command, operable program or batch file.', [Cmd.ProgramName]));
        ExecRes := 9009;
        ASession.ErrorLevel := 9009;
      end;
    end;

    Result := ExecRes;

    if Cmd.OpAnd and (ExecRes <> 0) then
      Break;
    if Cmd.OpOr and (ExecRes = 0) then
      Break;
  end;
end;

end.
