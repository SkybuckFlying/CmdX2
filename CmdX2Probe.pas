unit CmdX2Probe;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses CmdX2Types;

// Per Plan v5 §1.3: empirical probe removed. Fixed per-variable limit is
// CMDX2_ENV_VAR_LIMIT_CHARS. This unit is retained only as a stub.

function PerformCeilingProbe(ASession: TSession; AForce: Boolean = False): Int64;

implementation

function PerformCeilingProbe(ASession: TSession; AForce: Boolean): Int64;
begin
  Result := CMDX2_ENV_VAR_LIMIT_CHARS;
end;

end.