unit CmdX2Resolver;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections, CmdX2Types;

function IsBuiltInCommand(const ACmdName: string): Boolean;
function ResolveCommand(ASession: TSession; const ACmdName: string;
  out AResolvedPath: string): Boolean;

implementation

function IsBuiltInCommand(const ACmdName: string): Boolean;
var
  Cmd: string;
begin
  Cmd := LowerCase(Trim(ACmdName));
  Result :=
    (Cmd = 'dir') or (Cmd = 'cd') or (Cmd = 'chdir') or (Cmd = 'md') or
    (Cmd = 'mkdir') or (Cmd = 'rd') or (Cmd = 'rmdir') or (Cmd = 'del') or
    (Cmd = 'erase') or (Cmd = 'copy') or (Cmd = 'move') or (Cmd = 'ren') or
    (Cmd = 'rename') or (Cmd = 'type') or (Cmd = 'set') or (Cmd = 'path') or
    (Cmd = 'prompt') or (Cmd = 'title') or (Cmd = 'color') or (Cmd = 'cls') or
    (Cmd = 'ver') or (Cmd = 'vol') or (Cmd = 'date') or (Cmd = 'time') or
    (Cmd = 'pause') or (Cmd = 'exit') or (Cmd = 'echo') or (Cmd = 'shift') or
    (Cmd = 'call') or (Cmd = 'goto') or (Cmd = 'start') or (Cmd = 'assoc') or
    (Cmd = 'ftype') or (Cmd = 'setlocal') or (Cmd = 'endlocal') or
    (Cmd = 'pushd') or (Cmd = 'popd') or (Cmd = 'if') or (Cmd = 'else') or
    (Cmd = 'for') or (Cmd = 'rem');
end;

function TryFind(const ABase: string; ASession: TSession; out APath: string): Boolean;
var
  I: Integer;
  Candidate: string;
begin
  Result := False;
  APath := '';
  if FileExists(ABase) and not DirectoryExists(ABase) then
  begin
    APath := ABase;
    Exit(True);
  end;
  for I := 0 to ASession.PathExtList.Count - 1 do
  begin
    Candidate := ABase + ASession.PathExtList[I];
    if FileExists(Candidate) and not DirectoryExists(Candidate) then
    begin
      APath := Candidate;
      Exit(True);
    end;
  end;
end;

function ResolveCommand(ASession: TSession; const ACmdName: string;
  out AResolvedPath: string): Boolean;
var
  I: Integer;
  Name, Candidate: string;
begin
  Result := False;
  AResolvedPath := '';
  Name := Trim(ACmdName);
  if Name = '' then Exit;

  if ASession.ResolverCache.TryGetValue(LowerCase(Name), AResolvedPath) then
  begin
    if FileExists(AResolvedPath) then Exit(True);
    ASession.ResolverCache.Remove(LowerCase(Name));
  end;

  if (Pos('\', Name) > 0) or (Pos('/', Name) > 0) or
     ((Length(Name) >= 2) and (Name[2] = ':')) then
  begin
    if TryFind(ExpandFileName(Name), ASession, AResolvedPath) then
    begin
      ASession.ResolverCache.AddOrSetValue(LowerCase(Name), AResolvedPath);
      Exit(True);
    end;
    Exit;
  end;

  if not ASession.Environment.ContainsKey('NoDefaultCurrentDirectoryInExePath') then
  begin
    Candidate := IncludeTrailingPathDelimiter(ASession.Cwd) + Name;
    if TryFind(Candidate, ASession, AResolvedPath) then
    begin
      ASession.ResolverCache.AddOrSetValue(LowerCase(Name), AResolvedPath);
      Exit(True);
    end;
  end;

  for I := 0 to ASession.PathEntries.Count - 1 do
  begin
    Candidate := IncludeTrailingPathDelimiter(ASession.PathEntries[I]) + Name;
    if TryFind(Candidate, ASession, AResolvedPath) then
    begin
      ASession.ResolverCache.AddOrSetValue(LowerCase(Name), AResolvedPath);
      Exit(True);
    end;
  end;
end;

end.