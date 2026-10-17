unit CmdX2Batch;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses SysUtils, Classes, CmdX2Types;

function ExecuteBatchFile(ASession: TSession; const APath: string;
  AArgs: TStringList): Integer;

implementation

function ExecuteBatchFile(ASession: TSession; const APath: string;
  AArgs: TStringList): Integer;
begin
  Writeln(ErrOutput, 'Batch execution is not yet implemented (Milestone D).');
  Writeln(ErrOutput, 'File: ', APath);
  ASession.ErrorLevel := 9009;
  Result := 9009;
end;

end.