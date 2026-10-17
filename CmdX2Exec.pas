unit CmdX2Exec;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Winapi.Windows, Winapi.Messages,
  CmdX2Types, CmdX2Env, CmdX2Parser;

const
  // EXTENDED_STARTUPINFO_PRESENT: documented Windows constant.
  CMDX2_EXTENDED_STARTUPINFO_PRESENT = $00080000;

  // PROC_THREAD_ATTRIBUTE_HANDLE_LIST = ProcThreadAttributeValue(2, FALSE, TRUE, FALSE)
  //                                  = 2 | 0x00020000 = 0x00020002.
  // (The previous value 0x00020016 was wrong: it encoded attribute 22, not 2.)
  CMDX2_PROC_THREAD_ATTRIBUTE_HANDLE_LIST = $00020002;

type
  TStartupInfoExLocal = record
    StartupInfo: TStartupInfo;
    lpAttributeList: Pointer;
  end;

function _CreateProcessWEx(
  lpApplicationName: LPCWSTR;
  lpCommandLine: LPWSTR;
  lpProcessAttributes, lpThreadAttributes: PSecurityAttributes;
  bInheritHandles: BOOL;
  dwCreationFlags: DWORD;
  lpEnvironment: Pointer;
  lpCurrentDirectory: LPCWSTR;
  const lpStartupInfo: TStartupInfoExLocal;
  var lpProcessInformation: TProcessInformation): BOOL; stdcall;
  external 'kernel32.dll' name 'CreateProcessW';

function _InitProcThreadAttrList(
  lpAttributeList: Pointer; dwAttributeCount: DWORD; dwFlags: DWORD;
  var lpSize: NativeUInt): BOOL; stdcall;
  external 'kernel32.dll' name 'InitializeProcThreadAttributeList';

function _UpdateProcThreadAttr(
  lpAttributeList: Pointer; dwFlags: DWORD; Attribute: NativeUInt;
  lpValue: Pointer; cbSize: NativeUInt;
  lpPreviousValue: Pointer; lpReturnSize: Pointer): BOOL; stdcall;
  external 'kernel32.dll' name 'UpdateProcThreadAttribute';

procedure _DeleteProcThreadAttrList(lpAttributeList: Pointer); stdcall;
  external 'kernel32.dll' name 'DeleteProcThreadAttributeList';

function WinQuoteArg(const S: string): string;
function LaunchWithExplicitBlock(
  const AExePath: string;
  AArgs: TStringList;
  const ARedirects: TList<TRedirectOp>;
  AEnvBlock: Pointer;
  AWorkDir: string;
  out AExitCode: DWORD;
  out AError: string): Boolean;
function LaunchProcessDirect(ASession: TSession; const AExePath: string;
  AArgs: TStringList; const ARedirects: TList<TRedirectOp>): Integer;

implementation

function WinQuoteArg(const S: string): string;
var
  NeedsQuote: Boolean;
  I, N: Integer;
begin
  if S = '' then Exit('""');
  NeedsQuote := False;
  for I := 1 to Length(S) do
    if CharInSet(S[I], [' ', #9, '"']) then
    begin
      NeedsQuote := True;
      Break;
    end;
  if not NeedsQuote then Exit(S);

  Result := '"';
  I := 1;
  while I <= Length(S) do
  begin
    if S[I] = '\' then
    begin
      N := 0;
      while (I <= Length(S)) and (S[I] = '\') do
      begin
        Inc(N);
        Inc(I);
      end;
      if I > Length(S) then
        Result := Result + StringOfChar('\', N * 2)
      else if S[I] = '"' then
      begin
        Result := Result + StringOfChar('\', N * 2) + '\"';
        Inc(I);
      end
      else
        Result := Result + StringOfChar('\', N);
    end
    else if S[I] = '"' then
    begin
      Result := Result + '\"';
      Inc(I);
    end
    else
    begin
      Result := Result + S[I];
      Inc(I);
    end;
  end;
  Result := Result + '"';
end;

function BuildCmdLine(const AExePath: string; AArgs: TStringList): string;
var
  I: Integer;
begin
  Result := WinQuoteArg(AExePath);
  if Assigned(AArgs) then
    for I := 0 to AArgs.Count - 1 do
      Result := Result + ' ' + WinQuoteArg(AArgs[I]);
end;

function DupInheritableHandle(Source: THandle): THandle;
begin
  Result := INVALID_HANDLE_VALUE;
  if Source = INVALID_HANDLE_VALUE then Exit;
  if Source = 0 then Exit;  // NULL handle cannot be duplicated
  if not DuplicateHandle(GetCurrentProcess, Source, GetCurrentProcess,
    @Result, 0, True, DUPLICATE_SAME_ACCESS) then
    Result := INVALID_HANDLE_VALUE;
end;

function LaunchWithExplicitBlock(
  const AExePath: string;
  AArgs: TStringList;
  const ARedirects: TList<TRedirectOp>;
  AEnvBlock: Pointer;
  AWorkDir: string;
  out AExitCode: DWORD;
  out AError: string): Boolean;
var
  CmdLineStr: string;
  CmdLineBuf: PWideChar;
  BufSize: Integer;
  SIEX: TStartupInfoExLocal;
  AttrList: Pointer;
  AttrListSize: NativeUInt;
  PI: TProcessInformation;
  Handles: array[0..2] of THandle;
  ValidHandleCount: Integer;
  HIn, HOut, HErr: THandle;
  OpenedHandles: TList<THandle>;
  SA: TSecurityAttributes;
  I: Integer;
  Op: TRedirectOp;

  function OpenFileTarget(const ATarget: string; Access, Disp: DWORD): THandle;
  begin
    Result := CreateFileW(PWideChar(ATarget), Access,
      FILE_SHARE_READ or FILE_SHARE_WRITE,
      @SA, Disp, FILE_ATTRIBUTE_NORMAL, 0);
  end;

  procedure AppendHandle(H: THandle);
  begin
    if H = INVALID_HANDLE_VALUE then Exit;
    if H = 0 then Exit;
    Handles[ValidHandleCount] := H;
    Inc(ValidHandleCount);
  end;

begin
  Result := False;
  AError := '';
  AExitCode := 0;
  ValidHandleCount := 0;

  FillChar(SIEX, SizeOf(SIEX), 0);
  FillChar(PI, SizeOf(PI), 0);
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;

  OpenedHandles := TList<THandle>.Create;
  try
    HIn := DupInheritableHandle(GetStdHandle(STD_INPUT_HANDLE));
    HOut := DupInheritableHandle(GetStdHandle(STD_OUTPUT_HANDLE));
    HErr := DupInheritableHandle(GetStdHandle(STD_ERROR_HANDLE));
    if HIn <> INVALID_HANDLE_VALUE then OpenedHandles.Add(HIn);
    if HOut <> INVALID_HANDLE_VALUE then OpenedHandles.Add(HOut);
    if HErr <> INVALID_HANDLE_VALUE then OpenedHandles.Add(HErr);

    if Assigned(ARedirects) then
      for I := 0 to ARedirects.Count - 1 do
      begin
        Op := ARedirects[I];
        case Op.Kind of
          roToFile:
            begin
              if Op.Append then
                HOut := OpenFileTarget(Op.Target, FILE_APPEND_DATA, OPEN_ALWAYS)
              else
                HOut := OpenFileTarget(Op.Target, GENERIC_WRITE, CREATE_ALWAYS);
              if HOut <> INVALID_HANDLE_VALUE then
              begin
                OpenedHandles.Add(HOut);
                if Op.Source = rsStderr then HErr := HOut;
              end;
            end;
          roFromFile:
            begin
              HIn := OpenFileTarget(Op.Target, GENERIC_READ, OPEN_EXISTING);
              if HIn <> INVALID_HANDLE_VALUE then OpenedHandles.Add(HIn);
            end;
          roToNul:
            begin
              HOut := OpenFileTarget('NUL', GENERIC_WRITE, OPEN_EXISTING);
              if HOut <> INVALID_HANDLE_VALUE then
              begin
                OpenedHandles.Add(HOut);
                if Op.Source = rsStderr then HErr := HOut;
              end;
            end;
          roDup:
            begin
              if Op.Source = rsStderr then
              begin
                if Op.Target = '1' then HErr := HOut;
              end
              else if Op.Source = rsStdout then
              begin
                if Op.Target = '2' then HOut := HErr;
              end;
            end;
        end;
      end;

    // Build a compact list of valid handles only. The handle list
    // attribute must contain valid, inheritable handles. Including
    // INVALID_HANDLE_VALUE or NULL would cause the API to reject the
    // array with ERROR_BAD_LENGTH or ERROR_INVALID_HANDLE.
    AppendHandle(HIn);
    AppendHandle(HOut);
    AppendHandle(HErr);

    AttrList := nil;
    AttrListSize := 0;
    _InitProcThreadAttrList(nil, 1, 0, AttrListSize);
    if AttrListSize = 0 then
    begin
      AError := 'InitProcThreadAttrList size query failed';
      Exit;
    end;
    GetMem(AttrList, AttrListSize);
    try
      if not _InitProcThreadAttrList(AttrList, 1, 0, AttrListSize) then
      begin
        AError := Format('InitProcThreadAttrList failed (err %d)', [GetLastError]);
        Exit;
      end;
      try
        if ValidHandleCount > 0 then
        begin
          if not _UpdateProcThreadAttr(AttrList, 0,
            CMDX2_PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
            @Handles[0],
            NativeUInt(ValidHandleCount) * SizeOf(THandle),
            nil, nil) then
          begin
            AError := Format(
              'UpdateProcThreadAttr failed (err %d, handles: %d, size: %d)',
              [GetLastError, ValidHandleCount,
               NativeUInt(ValidHandleCount) * SizeOf(THandle)]);
            Exit;
          end;
        end;

        SIEX.StartupInfo.cb := SizeOf(SIEX);
        SIEX.StartupInfo.dwFlags := STARTF_USESTDHANDLES;
        SIEX.StartupInfo.hStdInput := HIn;
        SIEX.StartupInfo.hStdOutput := HOut;
        SIEX.StartupInfo.hStdError := HErr;
        SIEX.lpAttributeList := AttrList;

        CmdLineStr := BuildCmdLine(AExePath, AArgs);
        if Length(CmdLineStr) > CMDX2_CMDLINE_LIMIT_CHARS then
        begin
          AError := Format('Command line is %d chars; exceeds %d',
            [Length(CmdLineStr), CMDX2_CMDLINE_LIMIT_CHARS]);
          Exit;
        end;

        BufSize := (Length(CmdLineStr) + 1) * SizeOf(WideChar);
        GetMem(CmdLineBuf, BufSize);
        try
          for I := 1 to Length(CmdLineStr) do
            CmdLineBuf[I - 1] := CmdLineStr[I];
          CmdLineBuf[Length(CmdLineStr)] := #0;

          if not _CreateProcessWEx(PWideChar(AExePath), CmdLineBuf,
            nil, nil, True,
            CREATE_UNICODE_ENVIRONMENT or CMDX2_EXTENDED_STARTUPINFO_PRESENT,
            AEnvBlock, PWideChar(AWorkDir),
            SIEX, PI) then
          begin
            AError := Format('CreateProcessW failed; GetLastError = %d',
              [GetLastError]);
            Exit;
          end;

          WaitForSingleObject(PI.hProcess, INFINITE);
          GetExitCodeProcess(PI.hProcess, AExitCode);
          CloseHandle(PI.hProcess);
          CloseHandle(PI.hThread);
          Result := True;
        finally
          FreeMem(CmdLineBuf);
        end;
      finally
        _DeleteProcThreadAttrList(AttrList);
      end;
    finally
      FreeMem(AttrList);
    end;
  finally
    for I := 0 to OpenedHandles.Count - 1 do
      CloseHandle(OpenedHandles[I]);
    OpenedHandles.Free;
  end;
end;

function LaunchProcessDirect(ASession: TSession; const AExePath: string;
  AArgs: TStringList; const ARedirects: TList<TRedirectOp>): Integer;
var
  EnvCopy: TEnvironmentMap;
  BlockPtr: Pointer;
  BlockSize: Int64;
  BlockError, LaunchError: string;
  ChildExit: DWORD;
  K: string;
begin
  Result := 9009;
  EnvCopy := NewEnvironmentMap;
  try
    for K in ASession.Environment.Keys do
      EnvCopy.AddOrSetValue(K, ASession.Environment[K]);
    UpdatePerDriveEntries(ASession, EnvCopy);

    BlockPtr := BuildEnvironmentBlockUTF16(EnvCopy, BlockSize, BlockError);
    if BlockPtr = nil then
    begin
      Writeln(ErrOutput, 'Environment block error: ', BlockError);
      ASession.ErrorLevel := 9001;
      Exit(9001);
    end;
    try
      if not LaunchWithExplicitBlock(AExePath, AArgs, ARedirects, BlockPtr,
        ASession.Cwd, ChildExit, LaunchError) then
      begin
        Writeln(ErrOutput, Format('Error launching "%s": %s',
          [ExtractFileName(AExePath), LaunchError]));
        ASession.ErrorLevel := 9001;
        Exit(9001);
      end;
      Result := Integer(ChildExit);
      ASession.ErrorLevel := Result;
    finally
      FreeEnvironmentBlockUTF16(BlockPtr);
    end;
  finally
    EnvCopy.Free;
  end;
end;

end.