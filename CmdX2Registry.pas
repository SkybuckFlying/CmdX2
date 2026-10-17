unit CmdX2Registry;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, Windows, Messages, CmdX2Types;

type
  TRegistryPath = record
    RawValue: string;
    ValueType: string;
    Expanded: string;
  end;

function ReadMachinePath(out APath: TRegistryPath): Boolean;
function ReadUserPath(out APath: TRegistryPath): Boolean;
function MergeAndExpand(const AMachine, AUser: TRegistryPath;
  out AMerged, AError: string): Boolean;
function WriteUserPath(const ANewRaw, AType: string; out AError: string): Boolean;
procedure BroadcastEnvironmentChange;

implementation

const
  MACHINE_KEY = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';
  USER_KEY    = 'Environment';
  PATH_VALUE  = 'Path';

procedure CopyStringToBuffer(const S: string; ABuf: PWideChar);
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    ABuf[I - 1] := S[I];
  ABuf[Length(S)] := #0;
end;

function ReadRegValue(AHive: HKEY; const ASubKey, AValueName: string;
  out AValue, AType: string): Boolean;
var
  Key: HKEY;
  DataType, DataSize: DWORD;
  Buf: Pointer;
begin
  Result := False;
  AValue := '';
  AType := '';
  Key := 0;
  if RegOpenKeyExW(AHive, PWideChar(ASubKey), 0, KEY_READ, Key) <> ERROR_SUCCESS then
    Exit;
  try
    DataSize := 0;
    if RegQueryValueExW(Key, PWideChar(AValueName), nil, @DataType, nil, @DataSize) <> ERROR_SUCCESS then
      Exit;
    if (DataSize = 0) or (DataSize > 16 * 1024 * 1024) then Exit;
    GetMem(Buf, DataSize);
    try
      if RegQueryValueExW(Key, PWideChar(AValueName), nil, @DataType, Buf, @DataSize) <> ERROR_SUCCESS then
        Exit;
      case DataType of
        REG_SZ:        AType := 'REG_SZ';
        REG_EXPAND_SZ: AType := 'REG_EXPAND_SZ';
      else
        Exit;
      end;
      AValue := PWideChar(Buf);
      Result := True;
    finally
      FreeMem(Buf);
    end;
  finally
    RegCloseKey(Key);
  end;
end;

function ExpandValue(const ARaw: string): string;
var
  Buf: array[0..65535] of WideChar;
  N: DWORD;
begin
  if ARaw = '' then Exit('');
  N := ExpandEnvironmentStringsW(PWideChar(ARaw), @Buf[0], Length(Buf));
  if (N > 0) and (N <= DWORD(Length(Buf))) then
    Result := PWideChar(@Buf[0])
  else
    Result := ARaw;
end;

function ReadMachinePath(out APath: TRegistryPath): Boolean;
begin
  Result := ReadRegValue(HKEY_LOCAL_MACHINE, MACHINE_KEY, PATH_VALUE,
    APath.RawValue, APath.ValueType);
  if Result then
    APath.Expanded := ExpandValue(APath.RawValue)
  else
    APath.Expanded := '';
end;

function ReadUserPath(out APath: TRegistryPath): Boolean;
begin
  Result := ReadRegValue(HKEY_CURRENT_USER, USER_KEY, PATH_VALUE,
    APath.RawValue, APath.ValueType);
  if Result then
    APath.Expanded := ExpandValue(APath.RawValue)
  else
    APath.Expanded := '';
end;

function MergeAndExpand(const AMachine, AUser: TRegistryPath;
  out AMerged, AError: string): Boolean;
var
  Seen: TDictionary<string, Boolean>;
  MachineParts, UserParts: TStringList;
  Sb: TStringBuilder;
  I: Integer;

  procedure AppendPart(const P: string);
  var
    K: string;
  begin
    if P = '' then Exit;
    K := LowerCase(P);
    if Seen.ContainsKey(K) then Exit;
    Seen.Add(K, True);
    if Sb.Length > 0 then Sb.Append(';');
    Sb.Append(P);
  end;

begin
  Result := False;
  AError := '';
  AMerged := '';
  Seen := TDictionary<string, Boolean>.Create;
  Sb := TStringBuilder.Create;
  MachineParts := TStringList.Create;
  UserParts := TStringList.Create;
  try
    MachineParts.Delimiter := ';';
    MachineParts.StrictDelimiter := True;
    MachineParts.DelimitedText := AMachine.Expanded;

    UserParts.Delimiter := ';';
    UserParts.StrictDelimiter := True;
    UserParts.DelimitedText := AUser.Expanded;

    for I := 0 to MachineParts.Count - 1 do
      AppendPart(Trim(MachineParts[I]));
    for I := 0 to UserParts.Count - 1 do
      AppendPart(Trim(UserParts[I]));

    AMerged := Sb.ToString;
    if Length(AMerged) > CMDX2_ENV_VAR_LIMIT_CHARS then
    begin
      AError := Format(
        'Merged PATH is %d chars (machine %d + user %d); exceeds %d per-variable limit',
        [Length(AMerged), Length(AMachine.Expanded),
         Length(AUser.Expanded), CMDX2_ENV_VAR_LIMIT_CHARS]);
      Exit;
    end;
    Result := True;
  finally
    MachineParts.Free;
    UserParts.Free;
    Sb.Free;
    Seen.Free;
  end;
end;

function WriteUserPath(const ANewRaw, AType: string; out AError: string): Boolean;
var
  Key: HKEY;
  DataType: DWORD;
  Buf: Pointer;
  BufSize, DataSize: DWORD;
  OldValue, OldType: string;
begin
  Result := False;
  AError := '';

  if Length(ANewRaw) > CMDX2_ENV_VAR_LIMIT_CHARS then
  begin
    AError := Format('Value is %d chars; exceeds %d',
      [Length(ANewRaw), CMDX2_ENV_VAR_LIMIT_CHARS]);
    Exit;
  end;

  if RegOpenKeyExW(HKEY_CURRENT_USER, USER_KEY, 0, KEY_READ or KEY_WRITE, Key) <> ERROR_SUCCESS then
  begin
    AError := 'Could not open HKCU\Environment';
    Exit;
  end;

  try
    OldValue := '';
    OldType := 'REG_SZ';
    ReadRegValue(HKEY_CURRENT_USER, USER_KEY, PATH_VALUE, OldValue, OldType);

    if AType = 'REG_EXPAND_SZ' then DataType := REG_EXPAND_SZ else DataType := REG_SZ;
    BufSize := (Length(ANewRaw) + 1) * SizeOf(WideChar);
    GetMem(Buf, BufSize);
    try
      CopyStringToBuffer(ANewRaw, PWideChar(Buf));
      if RegSetValueExW(Key, PATH_VALUE, 0, DataType, Buf, BufSize) <> ERROR_SUCCESS then
      begin
        AError := Format('RegSetValueExW failed (err %d)', [GetLastError]);
        Exit;
      end;
    finally
      FreeMem(Buf);
    end;

    DataSize := 0;
    if RegQueryValueExW(Key, PATH_VALUE, nil, nil, nil, @DataSize) <> ERROR_SUCCESS then
    begin
      AError := 'Verify query failed';
      Exit;
    end;
    if DataSize = 0 then
    begin
      AError := 'Verify: value empty';
      Exit;
    end;
    GetMem(Buf, DataSize);
    try
      if RegQueryValueExW(Key, PATH_VALUE, nil, nil, Buf, @DataSize) <> ERROR_SUCCESS then
      begin
        AError := 'Verify read failed';
        Exit;
      end;
      if not SameStr(string(PWideChar(Buf)), ANewRaw) then
      begin
        AError := 'Verification mismatch; rolled back';
        if OldValue <> '' then
        begin
          BufSize := (Length(OldValue) + 1) * SizeOf(WideChar);
          GetMem(Buf, BufSize);
          try
            CopyStringToBuffer(OldValue, PWideChar(Buf));
            if OldType = 'REG_EXPAND_SZ' then DataType := REG_EXPAND_SZ else DataType := REG_SZ;
            RegSetValueExW(Key, PATH_VALUE, 0, DataType, Buf, BufSize);
          finally
            FreeMem(Buf);
          end;
        end;
        Exit;
      end;
    finally
      FreeMem(Buf);
    end;

    Result := True;
  finally
    RegCloseKey(Key);
  end;

  if Result then BroadcastEnvironmentChange;
end;

procedure BroadcastEnvironmentChange;
var
  Env: WideString;
  Res: NativeUInt;
begin
  Env := 'Environment';
{$WARN SYMBOL_DEPRECATED OFF}
{$WARN SYMBOL_PLATFORM OFF}
  SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
    LPARAM(PWideChar(Env)), SMTO_ABORTIFHUNG, 5000, Res);
{$WARN SYMBOL_PLATFORM DEFAULT}
{$WARN SYMBOL_DEPRECATED DEFAULT}
end;

end.