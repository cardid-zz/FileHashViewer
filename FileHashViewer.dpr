program FileHashViewer;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  System.Threading,
  System.Hash,
  System.Classes,
  System.Diagnostics,
  System.TimeSpan,
  Math,
  Winapi.Windows;

type
  TFileHash = record
    path: String;
    hash: String;
    calcTime: Double;
  end;
  THashFuture = IFuture<TFileHash>;
  TOnFilesCallback = reference to procedure(const files: TArray<String>);

procedure DoRecoursiveOnEachFileWithSorting(const APath: String; const AOnFilesCallBack: TOnFilesCallback);
begin
  try
    if not TDirectory.Exists(APath) then exit;
  except
  end;

  var dirs : TArray<String>;
  try
    dirs := Tdirectory.GetDirectories(APath);
  except
    // The specified path is too long.
    dirs := [];
  end;
  // Сразу всё сортируем
  TArray.Sort<String>(dirs, TStringComparer.Ordinal);

  for var d in dirs do begin
    DoRecoursiveOnEachFileWithSorting(d, AOnFilesCallBack);
  end;

  // Сразу всё сортируем
  var files : TArray<String>;
  try
    files := TDirectory.GetFiles(APath);
  except
    // The specified path is too long.
    files := [];
  end;

  TArray.Sort<String>(files, TStringComparer.Ordinal);
  AOnFilesCallBack(files);
end;

function HashFileCalculate(const APath: string): String; inline;
begin
  try
    Result := THashMD5.GetHashStringFromFile(APath);
  except
    Result := '';
  end;
end;

function HashFileCalculateFuture(const APath: String): THashFuture; inline;
begin
  // Вычисляем хеш файла в отдельном future
  Result := TTask.Future<TFileHash>(
          function : TFileHash
          var
            stopwatch : TStopwatch;
          begin
            stopwatch := TStopwatch.StartNew;

            Result.hash := hashFileCalculate(APath);
            Result.calcTime := stopwatch.Elapsed.TotalMilliseconds;

            Result.path := APath;
          end
        );
end;

procedure calcHashForAllFilesInDirectory(const APath: String; const AHashCallback: TProc<TFileHash>);
begin
  // Очередь, куда будем складывать результаты вычислений
  var queue := TQueue<THashFuture>.Create;
  var isDone := False;

  // Складыватель результатов в очередь
  var fileHashQueuer: TOnFilesCallback := procedure (const AFiles: TArray<string>)
      begin
        for var filename in AFiles do
          queue.Enqueue(HashFileCalculateFuture(filename));
      end
  ;

  // Выниматор готовых результатов из очереди
  var extractor := TTask.Run(
    procedure
    begin
      while not isDone do
      while queue.Count > 0 do begin
        var future := queue.Dequeue;
        try
          AHashCallback(future.value);
        except
          // ну вдруг чо
        end;
        future := nil;
      end;
    end
  );

  try
    // рекурсивно идем по каталогам и собираем файлы
    // полученный список файлов складываем в очередь
    // вынимаем готовые результаты из очереди и делаем дела
    DoRecoursiveOnEachFileWithSorting(APath, fileHashQueuer);

    // ждем, пока очередь кончится
    repeat
      sleep(0);
    until queue.Count = 0;

    isDone := True;
    extractor.Wait(100);
  finally
    extractor := nil;
    queue.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;

  var dirName := ParamStr(1);
  if dirName.IsEmpty then begin
    Writeln('Usage: ' +  TPath.GetFileName(ParamStr(0)) + ' <dirname>');
    Exit;
  end;

  var cmd: String := GetCommandLine;
  var showTimeCalculation := cmd.Contains('-showtime');
  var longestTime: Double;
  var longestTimeFile: String;

  // Печатор результата
  var printer : TProc<TFileHash>;
  if showTimeCalculation  then
    printer := procedure (AFileHash: TFileHash)
      begin
        if longestTime < AFileHash.calcTime then begin
          longestTime := AFileHash.calcTime;
          longestTimeFile := AFileHash.path;
        end;

        writeln(Format('%s %s %s', [AFileHash.hash, AFileHash.path, AFileHash.calcTime.ToString]));
      end
  else
    printer := procedure (AFileHash: TFileHash)
      begin
        writeln(Format('%s %s', [AFileHash.hash, AFileHash.path]));
      end;

  calcHashForAllFilesInDirectory(dirName, printer);

  if showTimeCalculation then begin
    Writeln('Max time hash calculation: ' + longestTime.ToString);
    Writeln('Max time hash calculation file: ' + longestTimeFile);
    Writeln('Done');
  end;
end.
