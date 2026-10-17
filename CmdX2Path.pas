unit CmdX2Path;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, CmdX2Types;

procedure RebuildPathEntries(ASession: TSession);

implementation

procedure RebuildPathEntries(ASession: TSession);
var
  Parts: TStringList;
  I: Integer;
  PathValue: string;
begin
  if not ASession.Environment.TryGetValue('PATH', PathValue) then
    PathValue := '';

  ASession.RawPath := PathValue;
  ASession.PathEntries.Clear;
  ASession.ResolverCache.Clear;

  Parts := TStringList.Create;
  try
    Parts.Delimiter := ';';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := ASession.RawPath;
    for I := 0 to Parts.Count - 1 do
      if Trim(Parts[I]) <> '' then
        ASession.PathEntries.Add(Trim(Parts[I]));
  finally
    Parts.Free;
  end;
end;

end.