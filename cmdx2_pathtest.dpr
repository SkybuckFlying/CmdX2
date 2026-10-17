program cmdx2_pathtest;

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

{ ============================================================
  cmdx2_pathtest — helper executable for the CmdX2 safety test.

  Modes:
    (no args)           Print the length of PATH as seen by this
                        process. Used by Step 3 of the safety test.
    dump                Print every environment variable, one per
                        line, in NAME=VALUE form.

                        SENSITIVITY WARNING: dump prints the
                        complete environment, which may contain
                        API keys, tokens, credentials, personal
                        paths, or other sensitive values. Do not
                        paste dump output into bug reports or
                        public channels without redaction.

                        The safety batch file deliberately does
                        NOT invoke this mode. It exists for
                        manual diagnostics only.

    check <substr>      Exit 0 if <substr> appears anywhere in
                        PATH, else exit 1.
    check-start <str>   Exit 0 if PATH starts with <str>, else 1.
    check-end <str>     Exit 0 if PATH ends with <str>, else 1.
    check-file <file>   Exit 0 if PATH is exactly equal to the
                        expected semicolon-joined content of
                        <file> (blanks skipped, entries trimmed),
                        else 1 with a diagnostic showing the
                        first difference.

  Exit codes:
    0   check succeeded
    1   check failed
    2   usage error (unknown mode, missing argument, unreadable
        file)
  ============================================================ }

uses
  SysUtils, Classes, Windows;

function ReadPathValue: string;
var
  Buf: PWideChar;
  BufLen, N: DWORD;
begin
  Result := '';
  BufLen := 4096;
  while True do
  begin
    GetMem(Buf, BufLen * SizeOf(WideChar));
    try
      // Initialize the first code unit so that an empty or missing
      // PATH produces a clean empty string rather than reading
      // uninitialized memory.
      Buf[0] := #0;
      N := GetEnvironmentVariableW('PATH', Buf, BufLen);

      if N = 0 then
      begin
        // PATH is absent or empty. GetEnvironmentVariableW does not
        // tell us which; both produce an empty result here, which is
        // the correct behavior for a path-source test.
        Result := '';
        Break;
      end;

      if N >= BufLen then
      begin
        BufLen := N + 4096;
        Continue;
      end;

      Result := Buf;
      Break;
    finally
      FreeMem(Buf);
    end;
  end;
end;

function BuildExpectedFromFile(const AFileName: string; out AExpected, AError: string): Boolean;
var
  SL: TStringList;
  I: Integer;
begin
  Result := False;
  AExpected := '';
  AError := '';
  if not FileExists(AFileName) then
  begin
    AError := 'File not found: ' + AFileName;
    Exit;
  end;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(AFileName);
    except
      on E: Exception do
      begin
        AError := 'Cannot read file: ' + E.Message;
        Exit;
      end;
    end;
    for I := 0 to SL.Count - 1 do
    begin
      if Trim(SL[I]) = '' then Continue;
      if AExpected <> '' then AExpected := AExpected + ';';
      AExpected := AExpected + Trim(SL[I]);
    end;
    Result := True;
  finally
    SL.Free;
  end;
end;

procedure PrintMismatchDiagnostic(const AExpected, AActual: string);
var
  I, L, StartPos: Integer;
begin
  Writeln(ErrOutput, 'PATH mismatch');
  Writeln(ErrOutput, '  Expected length: ', Length(AExpected));
  Writeln(ErrOutput, '  Actual length:   ', Length(AActual));

  L := Length(AExpected);
  if Length(AActual) < L then L := Length(AActual);

  for I := 1 to L do
    if AExpected[I] <> AActual[I] then
    begin
      StartPos := I - 20;
      if StartPos < 1 then StartPos := 1;
      Writeln(ErrOutput, '  First difference at position ', I);
      Writeln(ErrOutput, '  Expected: "...', Copy(AExpected, StartPos, 50), '"');
      Writeln(ErrOutput, '  Actual:   "...', Copy(AActual, StartPos, 50), '"');
      Exit;
    end;

  if Length(AExpected) < Length(AActual) then
    Writeln(ErrOutput, '  Actual has extra suffix: "',
      Copy(AActual, Length(AExpected) + 1, 50), '"')
  else if Length(AExpected) > Length(AActual) then
    Writeln(ErrOutput, '  Expected has extra suffix: "',
      Copy(AExpected, Length(AActual) + 1, 50), '"')
  else
    Writeln(ErrOutput, '  Lengths match but content differs (unreachable)');
end;

var
  Mode, Arg, PathValue, Expected, Err: string;
  Env, P: PWideChar;
begin
  if ParamCount = 0 then
  begin
    PathValue := ReadPathValue;
    Writeln(Length(PathValue));
    Halt(0);
  end;

  Mode := LowerCase(ParamStr(1));

  if Mode = 'dump' then
  begin
    // SENSITIVITY WARNING: prints every environment variable.
    // May include credentials, tokens, personal paths. Do not
    // paste into public channels without redaction. The safety
    // batch deliberately does not invoke this mode.
    Env := GetEnvironmentStringsW;
    if Env <> nil then
      try
        P := Env;
        while P^ <> #0 do
        begin
          Writeln(P);
          while P^ <> #0 do Inc(P);
          Inc(P);
        end;
      finally
        FreeEnvironmentStringsW(Env);
      end;
    Halt(0);
  end;

  if (Mode = 'check') and (ParamCount >= 2) then
  begin
    Arg := ParamStr(2);
    PathValue := ReadPathValue;
    if Pos(Arg, PathValue) > 0 then
      Halt(0)
    else
    begin
      Writeln(ErrOutput, 'Missing: ', Arg);
      Halt(1);
    end;
  end;

  if (Mode = 'check-start') and (ParamCount >= 2) then
  begin
    Arg := ParamStr(2);
    PathValue := ReadPathValue;
    if Copy(PathValue, 1, Length(Arg)) = Arg then
      Halt(0)
    else
    begin
      Writeln(ErrOutput, 'Not at start: ', Arg);
      Halt(1);
    end;
  end;

  if (Mode = 'check-end') and (ParamCount >= 2) then
  begin
    Arg := ParamStr(2);
    PathValue := ReadPathValue;
    if (Length(PathValue) >= Length(Arg)) and
       (Copy(PathValue, Length(PathValue) - Length(Arg) + 1, Length(Arg)) = Arg) then
      Halt(0)
    else
    begin
      Writeln(ErrOutput, 'Not at end: ', Arg);
      Halt(1);
    end;
  end;

  if (Mode = 'check-file') and (ParamCount >= 2) then
  begin
    Arg := ParamStr(2);
    if not BuildExpectedFromFile(Arg, Expected, Err) then
    begin
      Writeln(ErrOutput, Err);
      Halt(2);
    end;
    PathValue := ReadPathValue;
    if PathValue = Expected then
      Halt(0)
    else
    begin
      PrintMismatchDiagnostic(Expected, PathValue);
      Halt(1);
    end;
  end;

  Writeln(ErrOutput, 'Unknown mode: ', Mode);
  Halt(2);
end.