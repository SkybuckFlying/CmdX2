unit CmdX2Builtins;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, CmdX2Types, CmdX2Path;

function ExecuteBuiltinCommand(ASession: TSession; const ACmdName: string;
  AArgs: TStringList): Integer;

implementation

function ExecuteBuiltinCommand(ASession: TSession; const ACmdName: string;
  AArgs: TStringList): Integer;
var
  Cmd: string;
  I, EqPos: Integer;
  Names: TStringList;
  Key, Val: string;
begin
  Result := 0;
  Cmd := LowerCase(Trim(ACmdName));

  if Cmd = 'echo' then
  begin
    if Assigned(AArgs) and (AArgs.Count > 0) then
      for I := 0 to AArgs.Count - 1 do
      begin
        if I > 0 then Write(' ');
        Write(AArgs[I]);
      end;
    Writeln;
  end
  else if Cmd = 'ver' then
    Writeln('CmdX2 [Version 5.0 / Milestone A]')
  else if Cmd = 'exit' then
  begin
    if Assigned(AArgs) and (AArgs.Count > 0) then
      Result := StrToIntDef(AArgs[0], 0);
    ASession.ShouldExit := True;
  end
  else if Cmd = 'set' then
  begin
    if (not Assigned(AArgs)) or (AArgs.Count = 0) then
    begin
      Names := TStringList.Create;
      try
        for Key in ASession.Environment.Keys do
          Names.Add(Key);
        Names.CaseSensitive := False;
        Names.Sort;
        for I := 0 to Names.Count - 1 do
        begin
          Key := Names[I];
          if ASession.Environment.TryGetValue(Key, Val) then
            Writeln(Key + '=' + Val);
        end;
      finally
        Names.Free;
      end;
    end
    else
    begin
      EqPos := Pos('=', AArgs[0]);
      if EqPos > 0 then
      begin
        Key := Copy(AArgs[0], 1, EqPos - 1);
        Val := Copy(AArgs[0], EqPos + 1, Length(AArgs[0]) - EqPos);
        ASession.Environment.AddOrSetValue(Key, Val);
        if SameText(Key, 'PATH') then
          RebuildPathEntries(ASession);
      end;
    end;
  end
  else if Cmd = 'path' then
  begin
    if (not Assigned(AArgs)) or (AArgs.Count = 0) then
    begin
      if ASession.Environment.TryGetValue('PATH', Val) then
        Writeln(Val);
    end
    else
    begin
      ASession.Environment.AddOrSetValue('PATH', AArgs[0]);
      RebuildPathEntries(ASession);
    end;
  end
  else
  begin
    Writeln(ErrOutput, Format('''%s'' is not implemented in this build', [Cmd]));
    Result := 9009;
  end;
  ASession.ErrorLevel := Result;
end;

end.