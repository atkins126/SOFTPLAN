{-------------------------------------------------------------------------------
Tela: frmDonwload                                                Data:08/05/2021
Objetivo: Tela para download e gera??o do LOG

Dev.: S?rgio de Siqueira Silva

Data Altera??o: 08/05/2021
Dev.: S?rgio de Siqueira Silva
Altera??o: Substitui??o do componente IdHTTP (Indy) por NetHTTP (Net) para o
           o request em paginas HTTPS
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
  TfrmDownload = class(TForm)
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
    btnProgressoAtual: TRectangle;
    Image3: TImage;
    Label3: TLabel;
    procedure btnDownloadClick(Sender: TObject);
    procedure btnCancelarClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnProgressoAtualClick(Sender: TObject);
  private
    { Private declarations }
    FLog: TControlLog;
    FCodigoLog: Int64;

    FClient: THTTPClient;
    FGlobalStart: Cardinal;
    FDownloadStream: TStream;
    FAsyncResult: IAsyncResult;

    procedure Download(const PathDownload, URL: String);
    procedure ProcFinalDownload(const AsyncResult: IAsyncResult);
    procedure ThreadSincronizacaoGUI(const Sender: TObject; AContentLength,
      AReadCount: Int64; var Abort: Boolean);
  public
    { Public declarations }
  end;

var
  frmDownload: TfrmDownload;

implementation

{$R *.fmx}

{ TfrmImportacao }

{Cancelar: Pede a confirma??o e seta FAsyncResult para cancelado abortando Thread}
procedure TfrmDownload.btnCancelarClick(Sender: TObject);
begin
  if MessageDlg('Deseja realmente abortar o download?',
                TMsgDlgType.mtWarning,
                [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrNo then exit;

  btnCancelar.Enabled := False;
  FAsyncResult.Cancel;
end;

{Download: Confirma se tem algum link digitado, limpa o hist?rico do download
           anterior, seta o path para download, cria um novo log por fim start
           a Thread paralela atraves do IAsyncResult}
procedure TfrmDownload.btnDownloadClick(Sender: TObject);
var PathDownload: String;
begin
  if edtURL.Text = EmptyStr then
  begin
    ShowMessage('Preencha o link para download!');
    exit;
  end;

  Memo.Lines.Clear;

  //Sele??o do diretorio para o download
  SelectDirectory('Selecione uma pasta de destino','',PathDownload);
  PathDownload := PathDownload + '\' + GetURLFileName(edtURL.Text);

  btnDownload.Enabled := False;

  //Inclus?o dos dados no objeto de controle do Log
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

  //Procedure de Download com 1? Parametro Path para download 2? URL
  Download(PathDownload, edtURL.Text);
end;

{Exibe o progresso atual}
procedure TfrmDownload.btnProgressoAtualClick(Sender: TObject);
begin
  ShowMessage('Total de bytes at? o momento: ' + ProgressBar.Value.ToString +' bytes');
end;

{Procedure para executar no FINAL do download}
procedure TfrmDownload.ProcFinalDownload(const AsyncResult: IAsyncResult);
var LAsyncResponse: IHTTPResponse;
begin
  try
    LAsyncResponse := THTTPClient.EndAsyncHTTP(AsyncResult);

    //Thread de sincroniza??o com a GUI para exibir o resumo do download
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
    if ProgressBar.Value = ProgressBar.Max then
    begin
    if FLog.Acao(tacCarregar, FCodigoLog) then
      begin
        FLog.Acao(tacAlterar);
        FLog.Log.DataFim := Now;
        FLog.Acao(tacGravar);
      end;
    end;

    //Controle dos bot?es
    btnDownload.Enabled       := True;
    btnProgressoAtual.Enabled := False;
    btnCancelar.Enabled       := False;
  end;

end;

{Download: Procedure para download com dois parametros 1? path aonde o arquivo
           ira ser salvo e 2? URL do arquivo a ser baixado}
procedure TfrmDownload.Download(const PathDownload, URL: String);
var HTTPResponse   :IHTTPResponse;
    TamanhoArquivo :Int64;
begin
  try
    //Verifica o retorno da URL e armazena no response o tamanho
    HTTPResponse := FClient.Head(URL);
    TamanhoArquivo := HTTPResponse.ContentLength;
    Memo.Lines.Add(Format('Status do servi?o: %d - %s', [HTTPResponse.StatusCode, HTTPResponse.StatusText]));
    HTTPResponse := nil;

    //Manipula??o inicial do ProgressBar
    ProgressBar.Max := TamanhoArquivo;
    ProgressBar.Min := 0;
    ProgressBar.Value := 0;

    //Informa o inicio do download no memo
    Memo.Lines.Add(Format('Fazendo download de: "%s" (%d Bytes)' , [GetURLFileName(URL), TamanhoArquivo]));

    //Cria??o do arquivo (Stream) que recebera o download
    FDownloadStream := TFileStream.Create(PathDownload, fmCreate);
    FDownloadStream.Position := 0;

    //Tempo em milissegundos de start da Thread para calculo do tempo decorrido
    FGlobalStart := TThread.GetTickCount;

    {IAsyncResult e uma interface que internamente isola o processo em uma Thread
    paralela aonde inicio o download atrav?s do request e j? deixa registrado um
    processo para o final desse processo paralelo}
    FAsyncResult := FClient.BeginGet(ProcFinalDownload, URL, FDownloadStream);

  finally
    //Controle dos bot?es
    btnDownload.Enabled       := FAsyncResult = nil;
    btnCancelar.Enabled       := FAsyncResult <> nil;
    btnProgressoAtual.Enabled := FAsyncResult <> nil;
  end;
end;

//Procedure com Thread de sincroniza??o da GUI
procedure TfrmDownload.ThreadSincronizacaoGUI(const Sender: TObject;
          AContentLength, AReadCount: Int64; var Abort: Boolean);
var
  LTime: Cardinal;
  LSpeed: Integer;
begin
  //Tempo e velocidade se quiser mostrar na tela
  LTime := TThread.GetTickCount - FGlobalStart;
  LSpeed := (AReadCount * 1000) div LTime;

  //Atualiza ProgressBar
  TThread.Queue(nil,
    procedure
    begin
      ProgressBar.Value := AReadCount;
    end);
end;

{Na cria??o do form j? instancia o componente de HTTP para o Resquest
 e ja seta a procedure com Thread de sincroniza??o da GUI e cria o objeto
 de controle do Log}
procedure TfrmDownload.FormCreate(Sender: TObject);
begin
  FClient := THTTPClient.Create;
  FClient.OnReceiveData := ThreadSincronizacaoGUI;

  FLog := TControlLog.Create;
end;

//Na destrui??o faz a libera??o dos objetos da memoria
procedure TfrmDownload.FormDestroy(Sender: TObject);
begin
  if not btnDownload.Enabled then
  begin
    if MessageDlg('Deseja realmente abortar o download?',
                TMsgDlgType.mtWarning,
                [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0) = mrNo then abort;
  end;

  //Libera??o de objetos da memoria
  try
    FLog.Free;
    FDownloadStream.Free;
    FClient.Free;
  except
    //Anula freak de memoria para usu?rio
  end;
end;

end.
