unit CmdX2Builtins;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, StrUtils, CmdX2Types, CmdX2Config, CmdX2Path, CmdX2Resolver, CmdX2Probe, CmdX2Diagnostics
  {$IFDEF WINDOWS}
  , Windows
  {$ENDIF}
  ;

function ExecuteBuiltinCommand(var ASession: TSession; const ACmdName: string; AArgs: TStringList): Integer;

implementation

var
  DirectoryStack: TStringList = nil;

function ExecuteBuiltinCommand(var ASession: TSession; const ACmdName: string; AArgs: TStringList): Integer;
var
  Cmd, SubCmd, Arg1, Key, Val: string;
  I: Integer;
  NewEnv: TEnvironmentMap;
  F: TextFile;
  LineText: string;
  SR: TSearchRec;
  IsDirectory: Boolean;
begin
  Result := 0;
  Cmd := LowerCase(Trim(ACmdName));

  if not Assigned(DirectoryStack) then
    DirectoryStack := TStringList.Create;

  if (Cmd = 'echo') then
  begin
    if Assigned(AArgs) and (AArgs.Count > 0) then
    begin
      for I := 0 to AArgs.Count - 1 do
      begin
        if I > 0 then Write(' ');
        Write(AArgs[I]);
      end;
    end;
    Writeln;
  end
  else if (Cmd = 'cls') then
  begin
    Write(#27'[2J'#27'[H');
  end
  else if (Cmd = 'ver') then
  begin
    Writeln('CmdX2 [Version 2.0.0]');
    Writeln('Microsoft Windows / CmdX2 Compatible Environment');
  end
  else if (Cmd = 'pause') then
  begin
    Writeln('Press any key to continue . . . ');
    Readln;
  end
  else if (Cmd = 'cd') or (Cmd = 'chdir') then
  begin
    if (not Assigned(AArgs)) or (AArgs.Count = 0) then
      Writeln(ASession.Cwd)
    else
    begin
      Arg1 := AArgs[0];
      if SetCurrentDir(Arg1) then
      begin
        ASession.Cwd := GetCurrentDir;
        if Length(ASession.Cwd) >= 1 then
          ASession.Drive := ASession.Cwd[1];
      end
      else
      begin
        Writeln(ErrOutput, 'The system cannot find the path specified: ', Arg1);
        Result := 1;
      end;
    end;
  end
  else if (Cmd = 'pushd') then
  begin
    if Assigned(AArgs) and (AArgs.Count > 0) then
    begin
      DirectoryStack.Add(ASession.Cwd);
      Arg1 := AArgs[0];
      if SetCurrentDir(Arg1) then
      begin
        ASession.Cwd := GetCurrentDir;
        if Length(ASession.Cwd) >= 1 then
          ASession.Drive := ASession.Cwd[1];
      end
      else
      begin
        Writeln(ErrOutput, 'The system cannot find the path specified: ', Arg1);
        Result := 1;
      end;
    end;
  end
  else if (Cmd = 'popd') then
  begin
    if DirectoryStack.Count > 0 then
    begin
      Arg1 := DirectoryStack[DirectoryStack.Count - 1];
      DirectoryStack.Delete(DirectoryStack.Count - 1);
      if SetCurrentDir(Arg1) then
      begin
        ASession.Cwd := GetCurrentDir;
        if Length(ASession.Cwd) >= 1 then
          ASession.Drive := ASession.Cwd[1];
      end;
    end;
  end;

  if (Cmd = 'dir') then
  begin
    Arg1 := '*.*';
    if Assigned(AArgs) and (AArgs.Count > 0) then
      Arg1 := AArgs[0];

    if SysUtils.FindFirst(Arg1, faAnyFile, SR) = 0 then
    begin
      repeat
        IsDirectory := (SR.Attr and faDirectory) <> 0;
        if IsDirectory then
          Writeln(Format('%-12s %10d bytes  %s', ['<DIR>', SR.Size, SR.Name]))
        else
          Writeln(Format('%-12s %10d bytes  %s', ['', SR.Size, SR.Name]));
      until SysUtils.FindNext(SR) <> 0;
      SysUtils.FindClose(SR);
    end;
  end;

  if (Cmd = 'type') then
  begin
    if Assigned(AArgs) and (AArgs.Count > 0) then
    begin
      Arg1 := AArgs[0];
      if FileExists(Arg1) then
      begin
        AssignFile(F, Arg1);
        Reset(F);
        try
          while not Eof(F) do
          begin
            Readln(F, LineText);
            Writeln(LineText);
          end;
        finally
          CloseFile(F);
        end;
      end;
    end;
  end
  else if (Cmd = 'del') or (Cmd = 'erase') then
  begin
    if Assigned(AArgs) and (AArgs.Count > 0) then
    begin
      Arg1 := AArgs[0];
      if not SysUtils.DeleteFile(Arg1) then
        Result := 1;
    end;
  end;

  if (Cmd = 'md') or (Cmd = 'mkdir') then
  begin
    if Assigned(AArgs) and (AArgs.Count > 0) then
    begin
      Arg1 := AArgs[0];
      if not CreateDir(Arg1) then
        Result := 1;
    end;
  end
  else if (Cmd = 'rd') or (Cmd = 'rmdir') then
  begin
    if Assigned(AArgs) and (AArgs.Count > 0) then
    begin
      Arg1 := AArgs[0];
      if not RemoveDir(Arg1) then
        Result := 1;
    end;
  end
  else if (Cmd = 'set') then
  begin
    if (not Assigned(AArgs)) or (AArgs.Count = 0) then
    begin
      for Key in ASession.Environment.Keys do
      begin
        if ASession.Environment.TryGetValue(Key, Val) then
          Writeln(Key + '=' + Val);
      end;
    end;
  end
  else if (Cmd = 'setlocal') then
  begin
    NewEnv := TEnvironmentMap.Create;
    for Key in ASession.Environment.Keys do
    begin
      if ASession.Environment.TryGetValue(Key, Val) then
        NewEnv.Add(Key, Val);
    end;
    ASession.SetLocalStack.Add(NewEnv);
  end
  else if (Cmd = 'endlocal') then
  begin
    if ASession.SetLocalStack.Count > 0 then
    begin
      NewEnv := ASession.SetLocalStack[ASession.SetLocalStack.Count - 1];
      ASession.Environment.Free;
      ASession.Environment := NewEnv;
      ASession.SetLocalStack.Delete(ASession.SetLocalStack.Count - 1);
      ASession.ResolverCache.Clear;
    end;
  end
  else if (Cmd = 'exit') then
  begin
    ASession.ShouldExit := True;
  end
  else if (Cmd = 'cmdx2') then
  begin
    if (not Assigned(AArgs)) or (AArgs.Count = 0) then
      SubCmd := 'limits'
    else
      SubCmd := LowerCase(AArgs[0]);

    if SubCmd = 'limits' then
    begin
      if (AArgs.Count > 1) and SameText(AArgs[1], '--probe') then
        PerformCeilingProbe(ASession, True);
      PrintLimitsReport(ASession);
    end;
  end;

  ASession.ErrorLevel := Result;
end;

initialization

finalization
  if Assigned(DirectoryStack) then
    DirectoryStack.Free;

end.
