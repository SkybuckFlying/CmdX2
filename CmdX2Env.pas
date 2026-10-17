unit CmdX2Env;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, Windows, CmdX2Types;

procedure LoadCurrentEnvironment(ASession: TSession);
function BuildEnvironmentBlockUTF16(const AEnv: TEnvironmentMap;
  out ABlockSize: Int64; out AError: string): Pointer;
procedure FreeEnvironmentBlockUTF16(ABlock: Pointer);
procedure UpdatePerDriveEntries(ASession: TSession; const AEnv: TEnvironmentMap);

implementation

procedure LoadCurrentEnvironment(ASession: TSession);
var
  EnvBlock, P, LineStart: PWideChar;
  Entry, Name, Value: string;
  SepPos: Integer;
  Drive: Char;
begin
  ASession.Environment.Clear;
  ASession.PerDriveCwd.Clear;

  EnvBlock := GetEnvironmentStringsW;
  if EnvBlock = nil then Exit;
  try
    P := EnvBlock;
    while P^ <> #0 do
    begin
      LineStart := P;
      while P^ <> #0 do Inc(P);
      Entry := LineStart;
      if Entry <> '' then
      begin
        if Entry[1] = '=' then
          SepPos := Pos('=', Entry, 2)
        else
          SepPos := Pos('=', Entry);
        if SepPos > 1 then
        begin
          Name := Copy(Entry, 1, SepPos - 1);
          Value := Copy(Entry, SepPos + 1, Length(Entry));
          ASession.Environment.AddOrSetValue(Name, Value);
          if (Length(Name) >= 3) and (Name[1] = '=') and (Name[3] = ':') then
          begin
            Drive := UpCase(Name[2]);
            ASession.PerDriveCwd.AddOrSetValue(Drive, Value);
          end;
        end;
      end;
      Inc(P);
    end;
  finally
    FreeEnvironmentStringsW(EnvBlock);
  end;
  ASession.Cwd := GetCurrentDir;
end;

function BuildEnvironmentBlockUTF16(const AEnv: TEnvironmentMap;
  out ABlockSize: Int64; out AError: string): Pointer;
var
  Keys: TStringList;
  I, J: Integer;
  Key, Val, Pair: string;
  TotalChars: Int64;
  PBuffer, Cursor: PWideChar;
begin
  Result := nil;
  ABlockSize := 0;
  AError := '';

  Keys := TStringList.Create;
  try
    for Key in AEnv.Keys do Keys.Add(Key);
    Keys.CaseSensitive := False;
    Keys.Sort;

    TotalChars := 0;
    for I := 0 to Keys.Count - 1 do
    begin
      Key := Keys[I];
      if not AEnv.TryGetValue(Key, Val) then Continue;
      if Length(Val) > CMDX2_ENV_VAR_LIMIT_CHARS - Length(Key) - 1 then
      begin
        AError := Format('Variable "%s" value is %d chars; exceeds %d',
          [Key, Length(Val), CMDX2_ENV_VAR_LIMIT_CHARS]);
        Exit;
      end;
      TotalChars := TotalChars + Length(Key) + 1 + Length(Val) + 1;
    end;
    TotalChars := TotalChars + 1;

    ABlockSize := TotalChars * SizeOf(WideChar);
    GetMem(PBuffer, ABlockSize);
    try
      Cursor := PBuffer;
      for I := 0 to Keys.Count - 1 do
      begin
        Key := Keys[I];
        if not AEnv.TryGetValue(Key, Val) then Continue;
        Pair := Key + '=' + Val;
        for J := 1 to Length(Pair) do
        begin
          Cursor^ := Pair[J];
          Inc(Cursor);
        end;
        Cursor^ := #0;
        Inc(Cursor);
      end;
      Cursor^ := #0;
      Result := PBuffer;
    except
      FreeMem(PBuffer);
      raise;
    end;
  finally
    Keys.Free;
  end;
end;

procedure FreeEnvironmentBlockUTF16(ABlock: Pointer);
begin
  if Assigned(ABlock) then FreeMem(ABlock);
end;

procedure UpdatePerDriveEntries(ASession: TSession; const AEnv: TEnvironmentMap);
var
  Drive: Char;
  Key, Value: string;
  ToRemove: TList<string>;
begin
  ToRemove := TList<string>.Create;
  try
    for Key in AEnv.Keys do
      if (Length(Key) >= 3) and (Key[1] = '=') and (Key[3] = ':') then
        if not ASession.PerDriveCwd.ContainsKey(UpCase(Key[2])) then
          ToRemove.Add(Key);
    for Key in ToRemove do AEnv.Remove(Key);

    for Drive in ASession.PerDriveCwd.Keys do
    begin
      Key := '=' + Drive + ':';
      Value := ASession.PerDriveCwd[Drive];
      AEnv.AddOrSetValue(Key, Value);
    end;
  finally
    ToRemove.Free;
  end;
end;

end.