{-------------------------------------------------------------------------------
Tela: frmImportacao                                              Data:08/05/2021
Objetivo: Tela para download e gera��o do LOG

Dev.: S�rgio de Siqueira Silva

Data Altera��o: 09/05/2021
Dev.: S�rgio de Siqueira Silva
Altera��o: Inserido um memo para exibi��o do Status do download
-------------------------------------------------------------------------------}

unit Softplan.View.Dowload;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Layouts,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Memo, System.IOUtils, FMX.Edit,
  FMX.Objects, FMX.ScrollBox, uEnums, uFuncoes, DateUtils, System.Net.URLClient,
  System.Net.HttpClient, System.Net.HttpClientComponent, Softplan.Controller.Log,
  System.Threading;

type
  TfrmImportacao = class(TForm)
    LayoutContainer: TLayout;
    LayoutAcoesPesquisa: TLayout;
    Label1: TLabel;
    RectangleEdtNomeFantasia: TRectangle;
    edtURL: TEdit;
    btnDownload: TRectangle;
    Image1: TImage;
    Label2: TLabel;
    LayoutAcoes: TLayout;
    LayoutProgresso: TLayout;
    ProgressBar: TProgressBar;
    LabelVelocidade: TLabel;
    btnCancelar: TRectangle;
    Image2: TImage;
    Label4: TLabel;
    Memo: TMemo;
    StyleBook1: TStyleBook;
    procedure btnDownloadClick(Sender: TObject);
    procedure btnCancelarClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    { Private declarations }
    FLog: TControlLog;
    FCodigoLog: Int64;

    FClient: THTTPClient;
    FGlobalStart: Cardinal;
    FAsyncResult: IAsyncResult;
    FDownloadStream: TStream;

    procedure ProcFinalDownload(const AsyncResult: IAsyncResult);
    procedure ThreadSincronizacaoGUI(const Sender: TObject; AContentLength,
      AReadCount: Int64; var Abort: Boolean);
  public
    { Public declarations }
    procedure Download(const PathDownload, URL: String);
  end;

var
  frmImportacao: TfrmImportacao;

implementation

{$R *.fmx}


{ TfrmImportacao }

procedure TfrmImportacao.btnCancelarClick(Sender: TObject);
begin
  if MessageDlg('Deseja realmente abortar o download?',
                TMsgDlgType.mtWarning,
                [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrNo then exit;

  btnCancelar.Enabled := False;
  FAsyncResult.Cancel;
end;

procedure TfrmImportacao.btnDownloadClick(Sender: TObject);
var PathDownload: String;
begin
  Memo.Lines.Clear;

  //Sele��o do diretorio para o download
  SelectDirectory('Selecione uma pasta de destino','',PathDownload);
  PathDownload := PathDownload + '\' + GetURLFileName(edtURL.Text);

  btnDownload.Enabled := False;

  //Inclus�o dos dados no objeto de controle do Log
  try
    FLog.Acao(tacIncluir);
    FCodigoLog       := FLog.Log.Codigo;
    FLog.Log.URL     := edtURL.Text;
    FLog.Log.DataIni := Now;
    FLog.Acao(tacGravar);
  except
    btnDownload.Enabled := True;
    btnCancelar.Enabled := False;
  end;

  //Procedure de Download com 1� Parametro Path download 2� URL
  Download(PathDownload, edtURL.Text);
end;

{Procedure para executar no final do download}
procedure TfrmImportacao.ProcFinalDownload(const AsyncResult: IAsyncResult);
var LAsyncResponse: IHTTPResponse;
begin
  try
    LAsyncResponse := THTTPClient.EndAsyncHTTP(AsyncResult);

    //Thread de sincroniza��o com a GUI para exibir o resumo do download
    TThread.Synchronize(nil,
      procedure
      begin
        if ProgressBar.Max = ProgressBar.Value then
        begin
          Memo.Lines.Add('Arquivo baixado!');
        end else
        begin
          Memo.Lines.Add('Download abortado!');
        end;
      end);

  finally
    LAsyncResponse := nil;
    FreeandNil(FDownloadStream);

    //Grava no Log a Data e Hora final do download
    if FLog.Acao(tacAlterar) then
    begin
      FLog.Log.DataFim := Now;
      FLog.Acao(tacGravar);
    end;

    //Controle dos bot�es Download e Cancelar
    btnCancelar.Enabled := False;
    btnDownload.Enabled := True;
  end;

end;

{Download: Procedure para download com dois parametros 1� path aonde o arquivo
           ira ser salvo e 2� URL do arquivo a ser baixado}
procedure TfrmImportacao.Download(const PathDownload, URL: String);
var HTTPResponse   :IHTTPResponse;
    TamanhoArquivo :Int64;
begin
  try
    //Verifica o retorno da URL e armazena no response o tamanho
    HTTPResponse := FClient.Head(URL);
    TamanhoArquivo := HTTPResponse.ContentLength;
    Memo.Lines.Add(Format('Status do servi�o: %d - %s', [HTTPResponse.StatusCode, HTTPResponse.StatusText]));
    HTTPResponse := nil;

    //Manipula��o inicial do ProgressBar
    ProgressBar.Max := TamanhoArquivo;
    ProgressBar.Min := 0;
    ProgressBar.Value := 0;

    //Informa o inicio do download no memo
    Memo.Lines.Add(Format('Fazendo download de: "%s" (%d Bytes)' , [GetURLFileName(URL), TamanhoArquivo]));

    //Cria��o do arquivo (Stream) que recebera o download
    FDownloadStream := TFileStream.Create(PathDownload, fmCreate);
    FDownloadStream.Position := 0;

    //Tempo em milissegundos de start da Thread para calculo do tempo decorrido
    FGlobalStart := TThread.GetTickCount;

    {Inicia oficialmente o download com sincronismo na Thread e j� deixa
    registrado um processo para o final do donwload}
    FAsyncResult := FClient.BeginGet(ProcFinalDownload, URL, FDownloadStream);

  finally
    //Controle dos bot�es de download e cancelar
    btnCancelar.Enabled := FAsyncResult <> nil;
    btnDownload.Enabled := FAsyncResult = nil;
  end;
end;

//Procedure com Thread de sincroniza��o da GUI
procedure TfrmImportacao.ThreadSincronizacaoGUI(const Sender: TObject;
          AContentLength, AReadCount: Int64; var Abort: Boolean);
var
  LTime: Cardinal;
  LSpeed: Integer;
begin
  LTime := TThread.GetTickCount - FGlobalStart;
  LSpeed := (AReadCount * 1000) div LTime;
  TThread.Queue(nil,
    procedure
    begin
      ProgressBar.Value := AReadCount;
    end);
end;

{Na cria��o do form j� instancia o componente de HTTP para o Resquest
 e ja seta a procedure com Thread de sincroniza��o da GUI e cria o objeto
 de controle do Log}
procedure TfrmImportacao.FormCreate(Sender: TObject);
begin
  FClient := THTTPClient.Create;
  FClient.OnReceiveData := ThreadSincronizacaoGUI;

  FLog := TControlLog.Create;
end;

//Na destrui��o faz a libera��o dos objetos da memoria
procedure TfrmImportacao.FormDestroy(Sender: TObject);
begin
  if not btnDownload.Enabled then
  begin
    if MessageDlg('Deseja realmente abortar o download?',
                TMsgDlgType.mtWarning,
                [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrNo then abort;
  end;

  //Libera��o de objetos da memoria
  try
    FLog.Free;
    FDownloadStream.Free;
    FClient.Free;
  except
    //Anula freak de memoria para usu�rio
  end;
end;

end.
