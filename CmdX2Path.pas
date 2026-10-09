unit CmdX2Path;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, CmdX2Types;

procedure DeduplicatePathEntries(var ASession: TSession);
procedure NormalizePathEntries(var ASession: TSession);
procedure RebuildInMemoryPath(var ASession: TSession);
function GetPathLengthStats(const ASession: TSession; out ACharCount, AEntryCount: Integer; out AByteSize: Int64): string;

implementation

procedure NormalizePathEntries(var ASession: TSession);
var
  I: Integer;
  Entry: TPathEntrySource;
  P: string;
begin
  for I := 0 to ASession.PathEntries.Count - 1 do
  begin
    Entry := ASession.PathEntries[I];
    P := Entry.Path;
    if (Length(P) > 3) and (P[Length(P)] = PathDelim) then
      P := Copy(P, 1, Length(P) - 1);
    Entry.Path := P;
    ASession.PathEntries[I] := Entry;
  end;
end;

procedure DeduplicatePathEntries(var ASession: TSession);
var
  Seen: TDictionary<string, Boolean>;
  NewList: TList<TPathEntrySource>;
  I: Integer;
  Entry: TPathEntrySource;
  Key: string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  NewList := TList<TPathEntrySource>.Create;
  try
    for I := 0 to ASession.PathEntries.Count - 1 do
    begin
      Entry := ASession.PathEntries[I];
      Key := LowerCase(Entry.Path);
      if not Seen.ContainsKey(Key) then
      begin
        Seen.Add(Key, True);
        NewList.Add(Entry);
      end;
    end;

    ASession.PathEntries.Clear;
    for I := 0 to NewList.Count - 1 do
      ASession.PathEntries.Add(NewList[I]);
  finally
    Seen.Free;
    NewList.Free;
  end;
end;

procedure RebuildInMemoryPath(var ASession: TSession);
var
  I: Integer;
  Sb: TStringBuilder;
begin
  if ASession.Config.PathConfig.Normalize then
    NormalizePathEntries(ASession);

  if ASession.Config.PathConfig.Deduplicate then
    DeduplicatePathEntries(ASession);

  Sb := TStringBuilder.Create;
  try
    for I := 0 to ASession.PathEntries.Count - 1 do
    begin
      if I > 0 then
        Sb.Append(';');
      Sb.Append(ASession.PathEntries[I].Path);
    end;
    ASession.RawPath := Sb.ToString;
  finally
    Sb.Free;
  end;

  if Assigned(ASession.Environment) then
    ASession.Environment.AddOrSetValue('PATH', ASession.RawPath);
end;

function GetPathLengthStats(const ASession: TSession; out ACharCount, AEntryCount: Integer; out AByteSize: Int64): string;
var
  Status: string;
  Headroom: Int64;
begin
  ACharCount := Length(ASession.RawPath);
  AEntryCount := ASession.PathEntries.Count;
  AByteSize := ACharCount * SizeOf(Char);

  Headroom := ASession.Limits.MeasuredCeiling - AByteSize;
  if Headroom < 0 then
    Status := 'EXCEEDED'
  else if Headroom < (ASession.Limits.MeasuredCeiling div 10) then
    Status := 'WARNING'
  else
    Status := 'OK';

  Result := Format('PATH Length: %d chars, %d bytes across %d entries. Headroom: %d bytes. Status: %s',
                   [ACharCount, AByteSize, AEntryCount, Headroom, Status]);
end;

end.
