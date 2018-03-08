unit ServerModule;

interface

uses
  Classes,
  Vcl.ExtCtrls,WinApi.Messages,Windows,Forms, Vcl.Menus, Vcl.Controls,
  Vcl.StdCtrls, JvComponentBase, JvHidControllerClass,
  IdWebsocketServer, IdSSLOpenSSL, IdBaseComponent, IdComponent, IdServerIOHandler,
  IdIOHandler, IdIOHandlerSocket, IdIOHandlerStack, IdSSL;

type
  TFServerModule = class(TForm)
    TrayIcon1: TTrayIcon;
    PopupMenu1: TPopupMenu;
    Cerrar1: TMenuItem;

    Edit1: TEdit;
    HidController: TJvHidDeviceController;
    //wsSock: TsgcWebSocketServer;
    IdServerIOHandlerSSLOpenSSL1: TIdServerIOHandlerSSLOpenSSL;
    IdSSLIOHandlerSocketOpenSSL1: TIdSSLIOHandlerSocketOpenSSL;
    procedure FServerModuleCreate(Sender: TObject);
    procedure FServerModuleDestroy(Sender: TObject);
    procedure Cerrar1Click(Sender: TObject);
    procedure Edit1KeyPress(Sender: TObject; var Key: Char);
    procedure HidControllerArrival(HidDev: TJvHidDevice);
    procedure HidControllerRemoval(HidDev: TJvHidDevice);
    procedure HidControllerDeviceData(HidDev: TJvHidDevice; ReportID: Byte; const Data: Pointer; Size: Word);
    procedure IdServerIOHandlerSSLOpenSSL1GetPassword(var Password: string);
  protected
  private
    logFile:TFileStream;
    debug_level:Integer;
    lastMsg:String;
    scanner: TJvHidDevice;
    buf:AnsiString;
    wsServer : TIdWebsocketServer;
    //client : TIdHTTPWebsocketClient;
    procedure ShowMessageInMainthread(const aMsg: string) ;

  public
    userList:TStringList;
    procedure writeLog( x:AnsiString );
    procedure writeLogLN( const x:AnsiString );overload;
    procedure writeLogLN( const x:AnsiString ; level:Integer );overload;

  end;

var
    FServerModule:TFServerModule;

implementation

{$R *.dfm}

uses
    sysUtils,
    dialogs,
    IdServerIOHandlerWebsocket,
    Math,
    utils,
    IniFiles,
    StrUtils;

var FWinHandle : HWND;

type
    PDevBroadcastHdr  = ^DEV_BROADCAST_HDR;
    DEV_BROADCAST_HDR = packed record
        dbch_size       : DWORD;
        dbch_devicetype : DWORD;
        dbch_reserved   : DWORD;
    end;

    PDev_Broadcast_Port = ^DEV_BROADCAST_PORT;
    DEV_BROADCAST_PORT = record
        dbcp_size:DWORD ;
        dbcp_devicetype:DWORD ;
        dbcp_reserved:DWORD ;
        dbcp_name:PAnsiChar;
    end;

procedure TFServerModule.Cerrar1Click(Sender: TObject);
begin
    halt;
end;

const CRLF = #13#10;
const CKEY1 = 53761;
      CKEY2 = 32618;


//funcion para desencriptar
//un nombre de funcion tonto para evitar a los crackers ( soy uno de ellos ;)
//la "key" puede ser cualquier clave numerica 
function image_onChange_2(const S: String; Key: Word): String;
var   i, tmpKey  :Integer;
      RStr       :RawByteString;
      RStrB      :TBytes Absolute RStr;
      tmpStr     :string;
begin
  tmpStr:= UpperCase(S);
  SetLength(RStr, Length(tmpStr) div 2);
  i:= 1;
  try
    while (i < Length(tmpStr)) do begin
      RStrB[i div 2]:= StrToInt('$' + tmpStr[i] + tmpStr[i+1]);
      Inc(i, 2);
    end;
  except
    Result:= '';
    Exit;
  end;
  for i := 0 to Length(RStr)-1 do begin
    tmpKey:= RStrB[i];
    RStrB[i] := RStrB[i] xor (Key shr 8);
    Key := (tmpKey + Key) * CKEY1 + CKEY2;
  end;
  Result:= UTF8ToString(RStr);
end;


procedure TFServerModule.Edit1KeyPress(Sender: TObject; var Key: Char);
begin

    if key=#13 then
        wsServer.SendMessageToAll(Edit1.text);
        //wsSock.Broadcast(edit1.text);
end;

procedure TFServerModule.writeLog( x:AnsiString );
begin
    TThread.queue( nil,
        procedure begin
            x := formatDateTime( 'yyyy-mm-dd hh:nn:ss ' , now ) + x;
            logFile.writeBuffer( pointer(x)^ , length(x) );
        end );
end;

procedure TFServerModule.writeLogLN( const x:AnsiString );
begin
    writeLogLN( x ,  _MSG_ERROR_ );
end;

procedure TFServerModule.writeLogLN( const x:AnsiString ; level:Integer );
begin
    if debug_level = _MSG_DEBUG_ then
        trayIcon1.Hint := x;
    if (level = _MSG_ERROR_ ) or (level <= debug_level ) then
        writeLog( x + CRLF );
end;



procedure TFServerModule.ShowMessageInMainthread(const aMsg: string) ;
begin
  TThread.Synchronize(nil,
    procedure
    begin
        ShowMessage(aMsg);
    end);
end;

procedure TFServerModule.FServerModuleCreate(Sender: TObject);
      var logFileName:String;
begin

    wsServer := TIdWebsocketServer.Create(nil);
    wsServer.UseSSL := True;
    with TIdServerIOHandlerWebsocketSSL(wsServer.IOHandler).SSLOptions do begin
        CertFile := 'cert.pem';
        KeyFile := 'key.pem';
        Method  := sslvSSLv23;
        RootCertFile := 'root.pem';
    end;

    with TMemIniFile.Create( ExtractFilePath( Application.ExeName ) + APP_NAME+'.conf') do begin
        //wsSock.Port := strToIntDef( ReadString('websocket'  ,'port'         ,'10011'), 10011 );
        wsServer.DefaultPort := strToIntDef( ReadString('websocket'  ,'port'         ,'10011'), 10011 );
        debug_level := strToIntDef( ReadString('global' ,'debug_level','') , 0 );
        free;
    end;

    TIdServerIOHandlerWebsocketSSL(wsServer.IOHandler).OnGetPassword := IdServerIOHandlerSSLOpenSSL1GetPassword;

    Application.ShowMainForm := false;
    wsServer.Active      := True;

    logFileName := ExtractFilePath( Application.ExeName ) + APP_NAME+'.log';
    if not fileExists( logFileName ) then
        fileClose( fileCreate( logFileName ) );
    logFile := TFileStream.create( logFileName , Math.ifThen(debug_level >= _MSG_ERROR_, fmCreate, fmOpenWrite ) or fmShareDenyWrite );
    logFile.Position := logFile.Size;

    writeLogLN( 'Sistema iniciado' , _MSG_ALWAYS_ );

    //para guardar el ultimo mensaje enviado al log, y asi no repetirlo...
    lastMsg := '@';

end;

procedure TFServerModule.FServerModuleDestroy(Sender: TObject);
begin
    writeLogLN( 'Sistema Finalizado' , _MSG_ALWAYS_ );
    logFile.free;
    wsServer.Free;
end;

Const
  MyVendorID  = $0C2E;  // Put in your matching VendorID
  MyProductID = $0907;  // Put in your matching ProductID

procedure TFServerModule.HidControllerDeviceData(HidDev: TJvHidDevice;  ReportID: Byte; const Data: Pointer; Size: Word);
      var //buf   :AnsiString;
          posi  :Integer;
          text  :AnsiString;

     function removeChar(const S: AnsiString; Ch: AnsiChar):AnsiString;
          var I:Integer;
        begin
            result := S;
            for I := Length(result) downto 1 do begin
                if ( result[I] = Ch ) then
                    delete(result, I, 1);
            end;
        end;


     function AnsiPos_(const Substr:AnsiChar ; const S: AnsiString): Integer;
          var i:Integer;
        begin
              for i := 1 to length( S ) do
                    if S[i] = Substr then begin
                        result := i;
                        exit;
                    end

        end;

     function stringReplace_(const S:AnsiString; P:AnsiChar;  Q:AnsiString):AnsiString;
          var i:Integer;
        begin
                result := '';
                for i := 1 to length(S) do
                    if S[i] = P then
                        result := result + Q
                    else
                        result := result + S[i];
         end;
begin
    size := byte(AnsiString(data)[1]);
    buf := buf + AnsiString( copy( AnsiString(data) , 5 , size ) );
    if size < 56 then begin
        //QR ?
        if copy( buf , 1, 48 ) = 'https://portal.sidiv.registrocivil.cl/docstatus?' then
            buf := 'QR|'+stringReplace_( copy(buf,49) , '&', CRLF )//, [rfReplaceAll] )
        //PDF417
        else if buf[1] in ['0'..'9'] then begin
            posi := AnsiPos_( #0 , buf );
            text := copy( buf,1, posi-1 );  //rut + nose + apellido paterno
            //nacionalidad + fecha de vencimiento  (al no tener fecha de nacimiento esta ultima es inutil ya que no se puede deducir el anio de 4 digitos)
            buf  := copy( removeChar( copy( buf , posi ) , #0 ) , 1 ,  9 );
            posi := min( AnsiPos_( ' ' , text ) , 10 );

            buf := 'PDF417|RUN=' +copy( text , 1 , posi-2 )+'-'+copy(text,posi-1,1) + CRLF
                  +'APAT='+copy( text , 20 )            + CRLF
                  +'NACI='+copy( buf , 1, 3 )           + CRLF
                  +'VENC='+copy( buf , 4 );
            //text := copy( text , 1 , posi-1 )+'-'+copy(text,posi,1);
        //OCR (cedula nacional/pasaporte)
        end;// else if buf[1] in ['I','P'] then
            //por incompatibilidad de ansichar hacemos un chanchullo...
            //regeneramos la cadena y el buf queda listo para ser enviado, sino hago el chanchullo
            //broadcast envia una cadena vacia
        buf := stringReplace_( buf , #0 , '' );

        if buf<>'' then begin
            writeLogLN( 'Enviando:'+buf , _MSG_DEBUG_ );
            //wsSock.Broadcast(buf);
            wsServer.SendMessageToAll(buf);
            buf := '';
        end;

    end;

end;

procedure TFServerModule.HidControllerArrival(HidDev: TJvHidDevice);
      var scannerKeys:TStringList;
      const SCANNER_KEYS='scanner.keys';
begin
    if (HidDev.Attributes.VendorID=MyVendorID ) and (HidDev.Attributes.ProductID=MyProductID) then begin

        if not fileExists( SCANNER_KEYS ) then
            writeLogLN( 'No se encuentra archivo con seriales de scanner.' , _MSG_ERROR_ )
        else begin

            scannerKeys := TStringList.Create;
            scannerKeys.LineBreak := '';
            scannerKeys.loadFromFile( SCANNER_KEYS );
            scannerKeys.Text := image_onChange_2( scannerKeys.text , 1234 );

            if scannerKeys.IndexOf( HidDev.SerialNumber ) < 0 then
                writeLogLN( 'Scanner no autorizado:'+HidDev.SerialNumber , _MSG_ERROR_ )
            else if HidDev.CheckOut then begin
                scanner:=HidDev;
                //wsSock.active := true;
                wsServer.active := True;
                writeLogLN( 'Conectado scanner serie:'+scanner.SerialNumber );
            end;

        end;
    end;

end;

procedure TFServerModule.HidControllerRemoval(HidDev: TJvHidDevice);
begin
    if ((HidDev.Attributes.VendorID = MyVendorID) AND
        (HidDev.Attributes.ProductID = MyProductID)  ) then begin
        if Assigned(scanner) and (not scanner.IsPluggedIn) then
            HIDController.CheckIn(scanner);
        //wsSock.Active := false;
        wsServer.Active := false;
        writeLogLN( 'Desconectado...' );
    end;

end;

procedure TFServerModule.IdServerIOHandlerSSLOpenSSL1GetPassword(
  var Password: string);
begin
    password := 'fmsoft';
end;

end.
