program xbstrex;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  engine in 'engine.pas';

var
  XbeStrReader: TXbeStringsExtractor;

begin
  try
    XbeStrReader := TXbeStringsExtractor.Create;
    try
      XbeStrReader.Execute('default.xbe', 'output.csv');
    finally
      XbeStrReader.Free;
    end;
  except
    on E:Exception do
      Writeln(E.Classname, ': ', E.Message);
  end;
end.
