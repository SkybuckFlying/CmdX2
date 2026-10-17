program cmdx2;

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses
  SysUtils, Windows, Classes, Generics.Collections,
  CmdX2Types, CmdX2Registry, CmdX2Env, CmdX2Exec, CmdX2Path,
  CmdX2Parser, CmdX2Resolver, CmdX2Builtins, CmdX2Diagnostics;

function GetRawCommandLineTail(const AFlag: string): string;
var
  CmdLine, LowerCmd, LowerFlag: string;
  FlagPos, TailStart: Integer;
begin
  Result := '';
  CmdLine := GetCommandLineW;
  LowerCmd := LowerCase(CmdLine);
  LowerFlag := LowerCase(AFlag);
  FlagPos := Pos(LowerFlag, LowerCmd);
  if FlagPos = 0 then Exit;
  TailStart := FlagPos + Length(AFlag);
  while (TailStart <= Length(CmdLine)) and (CmdLine[TailStart] = ' ') do
    Inc(TailStart);
  Result := Copy(CmdLine, TailStart, Length(CmdLine) - TailStart + 1);
end;

function StripQuotes(const S: string): string;
begin
  Result := S;
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

procedure LoadStartupPath(ASession: TSession);
var
  MachinePath, UserPath: TRegistryPath;
  Merged, Err, InheritedPath: string;
begin
  if ASession.Environment.TryGetValue('CMDX2_SESSION', InheritedPath) then
    if ASession.Environment.TryGetValue('PATH', InheritedPath) and (InheritedPath <> '') then
    begin
      RebuildPathEntries(ASession);
      ASession.Environment.AddOrSetValue('CMDX2_SESSION', '1');
      Exit;
    end;

  if ASession.Environment.TryGetValue('CMDX2_INHERIT_PATH', InheritedPath) then
    if ASession.Environment.TryGetValue('PATH', InheritedPath) and (InheritedPath <> '') then
    begin
      RebuildPathEntries(ASession);
      ASession.Environment.AddOrSetValue('CMDX2_SESSION', '1');
      Exit;
    end;

  ReadMachinePath(MachinePath);
  ReadUserPath(UserPath);
  if MergeAndExpand(MachinePath, UserPath, Merged, Err) then
  begin
    ASession.Environment.AddOrSetValue('PATH', Merged);
    ASession.MachineRawPath := MachinePath.RawValue;
    ASession.UserRawPath := UserPath.RawValue;
    ASession.MachinePathType := MachinePath.ValueType;
    ASession.UserPathType := UserPath.ValueType;
    RebuildPathEntries(ASession);
  end
  else
  begin
    Writeln(ErrOutput, 'PATH merge error: ', Err);
    ASession.ErrorLevel := 9001;
  end;

  ASession.Environment.AddOrSetValue('CMDX2_SESSION', '1');
end;

procedure RunOnce(ASession: TSession; const ACommandLine: string);
var
  Toks: TTokenList;
  I: Integer;
  ExePath: string;
  Args: TStringList;
  Name: string;
begin
  Toks := Tokenize(ACommandLine);
  try
    if Toks.Count = 0 then Exit;
    Name := StripQuotes(Toks[0].Text);

    if IsBuiltInCommand(Name) then
    begin
      Args := TStringList.Create;
      try
        for I := 1 to Toks.Count - 1 do
          Args.Add(StripQuotes(Toks[I].Text));
        ExecuteBuiltinCommand(ASession, Name, Args);
      finally
        Args.Free;
      end;
      Exit;
    end;

    if ResolveCommand(ASession, Name, ExePath) then
    begin
      Args := TStringList.Create;
      try
        for I := 1 to Toks.Count - 1 do
          Args.Add(StripQuotes(Toks[I].Text));
        LaunchProcessDirect(ASession, ExePath, Args, nil);
      finally
        Args.Free;
      end;
    end
    else
    begin
      Writeln(ErrOutput, Format(
        '''%s'' is not recognized as an internal or external command, ' +
        'operable program or batch file.', [Name]));
      ASession.ErrorLevel := 9009;
    end;
  finally
    Toks.Free;
  end;
end;

var
  Session: TSession;
  Tail, Cmd: string;
begin
  try
    Session := TSession.Create;
    try
      LoadCurrentEnvironment(Session);
      LoadStartupPath(Session);

      if (ParamCount >= 1) and SameText(ParamStr(1), '/c') then
      begin
        Tail := GetRawCommandLineTail('/c');
        if Tail = '' then Halt(0);
        RunOnce(Session, Tail);
        Halt(Session.ErrorLevel);
      end;

      Writeln('CmdX2 [Milestone A]');
      Writeln('PATH length (in-memory): ', Length(Session.RawPath), ' chars');
      Writeln('Try:  cmdx2 /c cmdx2_pathtest.exe');
      Writeln('Type "exit" to quit.');
      Writeln;

      while not Session.ShouldExit do
      begin
        Write(Session.Cwd, '> ');
        Readln(Cmd);
        Cmd := Trim(Cmd);
        if Cmd = '' then Continue;
        if SameText(Cmd, 'exit') then Break;
        if SameText(Cmd, 'cmdx2 env-dump') then begin PrintEnvDump(Session); Continue; end;
        if SameText(Cmd, 'cmdx2 limits') then begin PrintLimitsReport(Session); Continue; end;
        RunOnce(Session, Cmd);
      end;
    finally
      Session.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'Fatal: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.