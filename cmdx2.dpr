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
  I, TailStart: Integer;
  InQuote: Boolean;
begin
  Result := '';
  CmdLine := GetCommandLineW;
  LowerCmd := LowerCase(CmdLine);
  LowerFlag := LowerCase(AFlag);

  InQuote := False;
  I := 1;
  while I <= Length(LowerCmd) do
  begin
    if LowerCmd[I] = '"' then
    begin
      InQuote := not InQuote;
      Inc(I);
      Continue;
    end;
    if InQuote then
    begin
      Inc(I);
      Continue;
    end;
    if (I + Length(LowerFlag) - 1 <= Length(LowerCmd)) and
       (Copy(LowerCmd, I, Length(LowerFlag)) = LowerFlag) and
       ((I = 1) or (LowerCmd[I - 1] = ' ')) and
       ((I + Length(LowerFlag) > Length(LowerCmd)) or
        (LowerCmd[I + Length(LowerFlag)] = ' ')) then
    begin
      TailStart := I + Length(LowerFlag);
      while (TailStart <= Length(CmdLine)) and (CmdLine[TailStart] = ' ') do
        Inc(TailStart);
      Result := Copy(CmdLine, TailStart, Length(CmdLine) - TailStart + 1);
      Exit;
    end;
    Inc(I);
  end;
end;

function StripQuotes(const S: string): string;
begin
  Result := S;
  if (Length(Result) >= 2) and (Result[1] = '"') and (Result[Length(Result)] = '"') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function LoadPathFromFile(const AFileName: string; out APath, AError: string): Boolean;
var
  SL: TStringList;
  I: Integer;
begin
  Result := False;
  APath := '';
  AError := '';
  if not FileExists(AFileName) then
  begin
    AError := 'Path file not found: ' + AFileName;
    Exit;
  end;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(AFileName);
    except
      on E: Exception do
      begin
        AError := 'Cannot read path file: ' + E.Message;
        Exit;
      end;
    end;
    for I := 0 to SL.Count - 1 do
    begin
      if Trim(SL[I]) = '' then Continue;
      if APath <> '' then APath := APath + ';';
      APath := APath + Trim(SL[I]);
    end;
    if Length(APath) > CMDX2_ENV_VAR_LIMIT_CHARS then
    begin
      AError := Format('Path file content is %d chars; exceeds %d',
        [Length(APath), CMDX2_ENV_VAR_LIMIT_CHARS]);
      Exit;
    end;
    Result := True;
  finally
    SL.Free;
  end;
end;

procedure LoadStartupPath(ASession: TSession; const APathFile: string);
var
  MachinePath, UserPath: TRegistryPath;
  Merged, Err, InheritedPath, FilePath, FileErr: string;
begin
  if APathFile <> '' then
  begin
    if not LoadPathFromFile(APathFile, FilePath, FileErr) then
    begin
      Writeln(ErrOutput, FileErr);
      ASession.ErrorLevel := 9001;
      Exit;
    end;
    ASession.Environment.AddOrSetValue('PATH', FilePath);
    ASession.UserRawPath := FilePath;
    ASession.UserPathType := 'FILE';
    RebuildPathEntries(ASession);
    ASession.Environment.AddOrSetValue('CMDX2_SESSION', '1');
    // No diagnostic output here. In /c mode, cmdx2 must print nothing
    // to stdout on a successful launch. In interactive mode, the banner
    // below reports the PATH source. A buffered write here would also
    // interleave incorrectly with the child's output.
    Exit;
  end;

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
  Tail, Cmd, PathFile: string;
  HasSlashC: Boolean;
  I: Integer;
begin
  PathFile := '';
  HasSlashC := False;
  I := 1;
  while I <= ParamCount do
  begin
    if SameText(ParamStr(I), '--path-file') then
    begin
      if I < ParamCount then
      begin
        PathFile := ParamStr(I + 1);
        Inc(I);
      end
      else
      begin
        Writeln(ErrOutput, '--path-file requires a value');
        Halt(1);
      end;
    end
    else if SameText(ParamStr(I), '/c') then
      HasSlashC := True;
    Inc(I);
  end;

  try
    Session := TSession.Create;
    try
      LoadCurrentEnvironment(Session);
      LoadStartupPath(Session, PathFile);

      if HasSlashC then
      begin
        Tail := GetRawCommandLineTail('/c');
        if Tail = '' then Halt(0);
        RunOnce(Session, Tail);
        Halt(Session.ErrorLevel);
      end;

      Writeln('CmdX2 [Milestone A]');
      if PathFile <> '' then
        Writeln('PATH source: file (', PathFile, ')')
      else
        Writeln('PATH source: registry (merged)');
      Writeln('PATH length (in-memory): ', Length(Session.RawPath), ' chars');
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