program cmdx2_pathtest;

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

uses
  SysUtils, Windows;

var
  Buf: PWideChar;
  BufLen, N: DWORD;
  Env, P: PWideChar;
begin
  if ParamCount >= 1 then
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
    Exit;
  end;

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
      Writeln(N);
      Break;
    finally
      FreeMem(Buf);
    end;
  end;
end.