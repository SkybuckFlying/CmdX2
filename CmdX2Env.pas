unit CmdX2Env;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Defaults, Generics.Collections, CmdX2Types;

procedure LoadCurrentEnvironment(var ASession: TSession);
function BuildEnvironmentBlockUTF16(const AEnvMap: TEnvironmentMap; out ABlockSize: Int64): Pointer;
procedure FreeEnvironmentBlockUTF16(ABlock: Pointer);

implementation

function CompareKeys(constref Left, Right: string): Integer;
begin
  Result := CompareText(Left, Right);
end;

procedure LoadCurrentEnvironment(var ASession: TSession);
var
  I: Integer;
  EnvStr, Name, Value: string;
  PosEq: Integer;
begin
  if not Assigned(ASession.Environment) then
    ASession.Environment := TEnvironmentMap.Create;

  ASession.Environment.Clear;

  for I := 1 to GetEnvironmentVariableCount do
  begin
    EnvStr := GetEnvironmentString(I);
    PosEq := Pos('=', EnvStr);
    if PosEq > 1 then
    begin
      Name := Copy(EnvStr, 1, PosEq - 1);
      Value := Copy(EnvStr, PosEq + 1, Length(EnvStr));
      ASession.Environment.AddOrSetValue(Name, Value);
    end;
  end;
end;

function BuildEnvironmentBlockUTF16(const AEnvMap: TEnvironmentMap; out ABlockSize: Int64): Pointer;
var
  Keys: TList<string>;
  I, J: Integer;
  Key, Val, Pair: string;
  CharCount, TotalChars: Int64;
  PBuffer: PChar;
  PWrite: PChar;
  Comparer: IComparer<string>;
begin
  Keys := TList<string>.Create;
  try
    for Key in AEnvMap.Keys do
      Keys.Add(Key);

    Comparer := TComparer<string>.Construct(CompareKeys);
    Keys.Sort(Comparer);

    TotalChars := 0;
    for I := 0 to Keys.Count - 1 do
    begin
      Key := Keys[I];
      if AEnvMap.TryGetValue(Key, Val) then
      begin
        Pair := Key + '=' + Val;
        TotalChars := TotalChars + Length(Pair) + 1; // +1 for null separator
      end;
    end;
    TotalChars := TotalChars + 1; // Extra final null character

    ABlockSize := TotalChars * SizeOf(Char);
    GetMem(PBuffer, ABlockSize);
    PWrite := PBuffer;

    for I := 0 to Keys.Count - 1 do
    begin
      Key := Keys[I];
      if AEnvMap.TryGetValue(Key, Val) then
      begin
        Pair := Key + '=' + Val;
        CharCount := Length(Pair);
        for J := 1 to CharCount do
        begin
          PWrite^ := Pair[J];
          Inc(PWrite);
        end;
        PWrite^ := #0;
        Inc(PWrite);
      end;
    end;
    PWrite^ := #0;

    Result := PBuffer;
  finally
    Keys.Free;
  end;
end;

procedure FreeEnvironmentBlockUTF16(ABlock: Pointer);
begin
  if Assigned(ABlock) then
    FreeMem(ABlock);
end;

end.
