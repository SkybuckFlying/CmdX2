program cmdx2_pathtest;

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses
  SysUtils, Windows;

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
      N := GetEnvironmentVariableW('PATH', Buf, BufLen);
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

var
  Mode, Arg, PathValue: string;
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

  Writeln(ErrOutput, 'Unknown mode: ', Mode);
  Halt(2);
end.