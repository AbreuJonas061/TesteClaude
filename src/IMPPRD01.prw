#Include "Protheus.ch"
#Include "FileIO.ch"
#Include "TopConn.ch"
#Include "TBIConn.ch"

/* ===========================================================================
   IMPPRD01 - Importacao de Produtos (SB1/SB5) via ExecAuto MATA010

   Compativel com Protheus 12.1.2410 / SmartClient HTML (navegador).

   Todo produto importado passa pelas validacoes nativas do sistema, pois a
   gravacao e feita exclusivamente pela rotina automatica MATA010 (X3_VALID,
   gatilhos, consistencias e pontos de entrada do cadastro de produtos).

   PONTOS DE MANUTENCAO (unicos lugares que normalmente precisam ser alterados):
      IP01Layout() ... ordem das colunas no modo "layout fixo"
      IP01Fixos() .... valores fixos aplicados a todos os registros
      IP01Ignora() ... nomes de coluna que devem ser desprezados

   No modo padrao (arquivo com cabecalho) NAO e necessario alterar o fonte
   para incluir um campo novo: basta acrescentar a coluna no arquivo.

   Autor..: Jonas - Analise de Sistemas
   =========================================================================== */

// --- Posicoes do array de configuracao (aCfg) -------------------------------
#DEFINE CFG_ARQUIVO   1    // Caminho completo do arquivo a importar (ja no servidor)
#DEFINE CFG_SEPAR     2    // Separador escolhido (0 = detectar automatico)
#DEFINE CFG_CODIF     3    // 1 = UTF-8 p/ ANSI  2 = nao converte  3 = ANSI p/ UTF-8
#DEFINE CFG_HEADER    4    // .T. = 1a linha traz os nomes dos campos
#DEFINE CFG_ATUALIZ   5    // .T. = altera produto ja cadastrado
#DEFINE CFG_SIMULA    6    // .T. = apenas valida, nao grava
#DEFINE CFG_DIRLOG    7    // Diretorio de log no servidor
#DEFINE CFG_SIZE      7

// --- Posicoes do array de resultado (aRes) ----------------------------------
#DEFINE RES_LIDAS     1    // Linhas de dados lidas
#DEFINE RES_INCLUI    2    // Produtos incluidos
#DEFINE RES_ALTERA    3    // Produtos alterados
#DEFINE RES_IGNORA    4    // Produtos ignorados (ja existem e nao atualiza)
#DEFINE RES_ERRO      5    // Linhas rejeitadas
#DEFINE RES_LOG       6    // Array de strings com o log detalhado
#DEFINE RES_REJEIT    7    // Array de {nLinha, cLinhaOriginal, cMotivo}
#DEFINE RES_SIZE      7

// --- Posicoes do dicionario em memoria (aDicio) -----------------------------
#DEFINE DIC_CAMPO     1
#DEFINE DIC_TIPO      2
#DEFINE DIC_TAM       3
#DEFINE DIC_DEC       4
#DEFINE DIC_TITULO    5
#DEFINE DIC_ARQUIVO   6

// --- Posicoes do mapa de colunas (aMapa) ------------------------------------
#DEFINE MAP_COLUNA    1
#DEFINE MAP_CAMPO     2
#DEFINE MAP_TIPO      3
#DEFINE MAP_TAM       4
#DEFINE MAP_DEC       5
#DEFINE MAP_ARQUIVO   6

// --- Constantes gerais ------------------------------------------------------
#DEFINE IMP_VERSAO    "1.00"
#DEFINE IMP_DIRPAD    "\imp_produtos\"
#DEFINE IMP_DIRLOG    "\imp_produtos\log\"
#DEFINE IMP_TAB       Chr(9)
#DEFINE IMP_ASPA      Chr(34)
#DEFINE IMP_BOM       Chr(239) + Chr(187) + Chr(191)
#DEFINE IMP_MAXLOG    500       // Linhas de log exibidas em tela (o arquivo traz tudo)


/*/{Protheus.doc} IMPPRD01
Ponto de entrada da rotina. Abre a tela de parametrizacao da importacao.

Cadastro no menu (SIGAMDI) -> Programa: U_IMPPRD01 / Tipo: Funcao Protheus

@author  Jonas
@since   09/2026
@version 1.00
/*/
User Function IMPPRD01()

    Local aArea := FWGetArea()

    // Garante os diretorios de trabalho no servidor
    IP01MkDir(IMP_DIRPAD)
    IP01MkDir(IMP_DIRLOG)

    IP01Tela()

    FWRestArea(aArea)

Return Nil


// ===========================================================================
// AREA DE MANUTENCAO - normalmente e so aqui que voce precisa mexer
// ===========================================================================

/*/{Protheus.doc} IP01Layout
Layout de colunas usado quando o arquivo NAO possui linha de cabecalho.
A ordem do array e exatamente a ordem das colunas no arquivo.

Para incluir/remover um campo basta acrescentar ou comentar uma linha aqui.

Estrutura de cada elemento:
   [1] Nome do campo (tabela SB1 ou SB5)
   [2] Comentario livre (usado apenas no arquivo modelo)

@return aLay Array com o layout posicional
/*/
Static Function IP01Layout()

    Local aLay := {}

    //         Campo         Descricao
    aAdd(aLay, {"B1_COD"   , "Codigo do produto"        })
    aAdd(aLay, {"B1_DESC"  , "Descricao"                })
    aAdd(aLay, {"B1_TIPO"  , "Tipo (SX5 tabela 02)"     })
    aAdd(aLay, {"B1_UM"    , "Unidade de medida (SAH)"  })
    aAdd(aLay, {"B1_LOCPAD", "Armazem padrao (NNR)"     })
    aAdd(aLay, {"B1_GRUPO" , "Grupo de produtos (SBM)"  })
    aAdd(aLay, {"B1_POSIPI", "NCM"                      })
    aAdd(aLay, {"B1_ORIGEM", "Origem da mercadoria"     })
    aAdd(aLay, {"B1_PRV1"  , "Preco de venda"           })
    aAdd(aLay, {"B1_CUSTD" , "Custo standard"           })
    aAdd(aLay, {"B1_PICM"  , "Aliquota de ICMS"         })
    aAdd(aLay, {"B1_IPI"   , "Aliquota de IPI"          })
    aAdd(aLay, {"B1_CONTA" , "Conta contabil (CT1)"     })
    aAdd(aLay, {"B1_MSBLQL", "Bloqueado (1=Sim 2=Nao)"  })

Return aLay


/*/{Protheus.doc} IP01Fixos
Valores fixos aplicados a TODOS os registros importados.
Sao aplicados apenas quando a coluna nao veio preenchida no arquivo, ou seja,
o conteudo do arquivo sempre tem prioridade.

@return aFix Array de {cCampo, xValor}
/*/
Static Function IP01Fixos()

    Local aFix := {}

    //         Campo         Valor
    aAdd(aFix, {"B1_MSBLQL", "2"})    // Produto liberado

    // Exemplos - descomente/ajuste conforme a necessidade da sua base:
    // aAdd(aFix, {"B1_LOCPAD", "01"})
    // aAdd(aFix, {"B1_ORIGEM", "0" })
    // aAdd(aFix, {"B1_TIPO"  , "ME" })

Return aFix


/*/{Protheus.doc} IP01Ignora
Nomes de coluna que devem ser desprezados na leitura do cabecalho.
Serve para arquivos que trazem colunas de controle do usuario.

@return aIgn Array de strings (maiusculas, sem espacos)
/*/
Static Function IP01Ignora()
Return {"IGNORAR", "OBS", "OBSERVACAO", "#", "CONTROLE", "ERRO", "MOTIVO"}


// ===========================================================================
// INTERFACE
// ===========================================================================

/*/{Protheus.doc} IP01Tela
Monta a tela de parametrizacao da importacao.
Utiliza somente componentes compativeis com o SmartClient HTML (navegador).
/*/
Static Function IP01Tela()

    Local oDlg
    Local oFont
    Local oGetArq
    Local oGetLog
    Local oCboSep
    Local oCboCod
    Local oChkHea
    Local oChkAtu
    Local oChkSim

    Local nLin      := 0

    Local cArquivo  := Space(250)
    Local cDirLog   := PadR(IMP_DIRLOG, 250)

    Local nSepar    := 1
    Local nCodif    := 1

    Local lHeader   := .T.
    Local lAtualiz  := .F.
    Local lSimula   := .F.

    Local aSepar    := {"1=Ponto-e-virgula  ( ; )", ;
                        "2=Pipe  ( | )", ;
                        "3=Tabulacao  (TAB)", ;
                        "4=Virgula  ( , )", ;
                        "5=Detectar automaticamente"}
    Local aCodif    := {"1=Arquivo UTF-8  (converter)", ;
                        "2=Arquivo ANSI / Excel  (nao converter)", ;
                        "3=Ambiente UTF-8  (converter de ANSI)"}

    oFont := TFont():New("Arial", , -12, .T., .T.)

    DEFINE MSDIALOG oDlg TITLE "Importacao de Produtos via ExecAuto - versao " + IMP_VERSAO ;
           FROM 0, 0 TO 200, 700 PIXEL

    nLin := 8
    @ nLin, 010 SAY "Importacao de produtos (SB1/SB5) com as validacoes nativas do Protheus" ;
                SIZE 320, 10 FONT oFont PIXEL OF oDlg

    nLin += 18
    @ nLin, 010 SAY "Arquivo:" SIZE 042, 08 PIXEL OF oDlg
    @ nLin - 1, 055 MSGET oGetArq VAR cArquivo SIZE 240, 10 PIXEL OF oDlg
    TButton():New(nLin - 1, 299, "...", oDlg, ;
                  {|| cArquivo := IP01Busca(cArquivo), oGetArq:Refresh() }, ;
                  018, 011, , , .F., .T., .F., , .F., , , .F.)

    nLin += 17
    @ nLin, 010 SAY "Separador:" SIZE 042, 08 PIXEL OF oDlg
    @ nLin - 1, 055 COMBOBOX oCboSep VAR nSepar ITEMS aSepar SIZE 120, 10 PIXEL OF oDlg

    @ nLin, 190 SAY "Codificacao:" SIZE 045, 08 PIXEL OF oDlg
    @ nLin - 1, 238 COMBOBOX oCboCod VAR nCodif ITEMS aCodif SIZE 145, 10 PIXEL OF oDlg

    nLin += 20
    @ nLin, 012 CHECKBOX oChkHea VAR lHeader ;
                PROMPT "A primeira linha do arquivo contem os nomes dos campos (recomendado)" ;
                SIZE 300, 09 PIXEL OF oDlg

    nLin += 13
    @ nLin, 012 CHECKBOX oChkAtu VAR lAtualiz ;
                PROMPT "Atualizar produtos ja cadastrados (quando desmarcado, sao ignorados)" ;
                SIZE 300, 09 PIXEL OF oDlg

    nLin += 13
    @ nLin, 012 CHECKBOX oChkSim VAR lSimula ;
                PROMPT "Somente simular - valida o arquivo e nao grava nada" ;
                SIZE 300, 09 PIXEL OF oDlg

    nLin += 20
    @ nLin, 010 SAY "Dir. log:" SIZE 042, 08 PIXEL OF oDlg
    @ nLin - 1, 055 MSGET oGetLog VAR cDirLog SIZE 240, 10 PIXEL OF oDlg

    nLin += 22
    TButton():New(nLin, 010, "Gerar arquivo modelo", oDlg, {|| IP01Modelo() }, ;
                  078, 013, , , .F., .T., .F., , .F., , , .F.)

    TButton():New(nLin, 195, "Importar", oDlg, ;
                  {|| IP01Inicia(cArquivo, nSepar, nCodif, ;
                                 lHeader, lAtualiz, lSimula, cDirLog) }, ;
                  058, 013, , , .F., .T., .F., , .F., , , .F.)

    TButton():New(nLin, 258, "Sair", oDlg, {|| oDlg:End() }, ;
                  058, 013, , , .F., .T., .F., , .F., , , .F.)

    ACTIVATE MSDIALOG oDlg CENTERED

Return Nil


/*/{Protheus.doc} IP01Busca
Abre a selecao de arquivo na maquina do usuario (estacao/navegador).

cGetFile() com GETF_LOCALHARD abre o dialogo nativo na maquina LOCAL de
quem esta usando o sistema - nunca o disco do servidor. O que acontece em
seguida depende do SmartClient:

   HTML (navegador) . o proprio framework transfere o arquivo para uma
                      area temporaria do AppServer e devolve um caminho
                      ja legivel no servidor;
   Desktop (exe) .... o caminho devolvido e da estacao e precisa ser
                      trazido para o servidor por CpyT2S().

A leitura sempre ocorre no servidor, entao a funcao garante que o caminho
devolvido seja acessivel pelo AppServer nos dois casos.

@param cAtual Caminho atualmente informado
@return cRet  Caminho do arquivo, ja no servidor
/*/
Static Function IP01Busca(cAtual)

    Local cRet  := AllTrim(cAtual)
    Local cArq  := ""
    Local cMasc := "Arquivos CSV|*.csv|Arquivos TXT|*.txt|Todos|*.*"

    cArq := cGetFile(cMasc, "Selecione o arquivo de produtos", 0, ;
                     "", .F., GETF_LOCALHARD, .F., .F.)

    If Empty(cArq)
        Return PadR(cRet, 250)
    EndIf

    // O AppServer ja enxerga o arquivo: nada a transferir
    If File(cArq)
        Return PadR(cArq, 250)
    EndIf

    // Caminho da estacao - traz para o servidor (destino e o DIRETORIO)
    IP01MkDir(IMP_DIRPAD)

    If CpyT2S(cArq, IMP_DIRPAD, .F.)
        cRet := IMP_DIRPAD + IP01NmArq(cArq)
    Else
        MsgStop("Nao foi possivel transferir o arquivo para o servidor." + CRLF + CRLF + ;
                "Copie o arquivo para " + IMP_DIRPAD + " no servidor e informe " + ;
                "esse caminho diretamente no campo Arquivo.", "Transferencia")
    EndIf

Return PadR(cRet, 250)


/*/{Protheus.doc} IP01Inicia
Valida os parametros da tela, dispara o processamento com regua e exibe o log.
/*/
Static Function IP01Inicia(cArquivo, nSepar, nCodif, lHeader, lAtualiz, lSimula, cDirLog)

    Local aCfg    := Array(CFG_SIZE)
    Local aRes    := {}
    Local cArqLog := ""
    Local cArqRej := ""
    Local cMsg    := ""

    If Empty(cArquivo)
        MsgStop("Informe o arquivo a ser importado.", "Atencao")
        Return Nil
    EndIf

    If Empty(cDirLog)
        cDirLog := IMP_DIRLOG
    EndIf

    IP01MkDir(cDirLog)

    If !File(AllTrim(cArquivo))
        MsgStop("Arquivo nao localizado no servidor:" + CRLF + AllTrim(cArquivo) + CRLF + CRLF + ;
                "Selecione o arquivo novamente pelo botao '...'. Se o erro persistir, " + ;
                "copie o arquivo para " + IMP_DIRPAD + " no servidor e informe " + ;
                "esse caminho diretamente no campo.", "Atencao")
        Return Nil
    EndIf

    If !lSimula .And. !MsgYesNo("Confirma a importacao do arquivo abaixo?" + CRLF + CRLF + ;
                                AllTrim(cArquivo) + CRLF + CRLF + ;
                                "Atualizar produtos existentes: " + ;
                                IIf(lAtualiz, "SIM", "NAO"), "Confirmacao")
        Return Nil
    EndIf

    aCfg[CFG_ARQUIVO] := AllTrim(cArquivo)
    aCfg[CFG_SEPAR]   := IIf(nSepar == 5, 0, nSepar)
    aCfg[CFG_CODIF]   := nCodif
    aCfg[CFG_HEADER]  := lHeader
    aCfg[CFG_ATUALIZ] := lAtualiz
    aCfg[CFG_SIMULA]  := lSimula
    aCfg[CFG_DIRLOG]  := AllTrim(cDirLog)

    Processa({|| aRes := IP01Proc(aCfg) }, "Importacao de Produtos", "Aguarde...", .F.)

    If Empty(aRes)
        Return Nil
    EndIf

    cArqLog := IP01GrvLog(aCfg, aRes)
    cArqRej := IP01GrvRej(aCfg, aRes)

    cMsg := IIf(lSimula, "SIMULACAO CONCLUIDA - nada foi gravado", "IMPORTACAO CONCLUIDA") + CRLF + CRLF
    cMsg += "Linhas lidas ...: " + cValToChar(aRes[RES_LIDAS])  + CRLF
    cMsg += "Incluidos ......: " + cValToChar(aRes[RES_INCLUI]) + CRLF
    cMsg += "Alterados ......: " + cValToChar(aRes[RES_ALTERA]) + CRLF
    cMsg += "Ignorados ......: " + cValToChar(aRes[RES_IGNORA]) + CRLF
    cMsg += "Rejeitados .....: " + cValToChar(aRes[RES_ERRO])   + CRLF + CRLF
    cMsg += "Arquivo de log .: " + cArqLog + CRLF
    If !Empty(cArqRej)
        cMsg += "Rejeitados .....: " + cArqRej + CRLF
    EndIf

    IP01VerLog(cMsg, aRes[RES_LOG])

Return Nil


/*/{Protheus.doc} IP01VerLog
Exibe em tela o resumo e o log detalhado da importacao.
/*/
Static Function IP01VerLog(cResumo, aLog)

    Local oDlg
    Local oMemRes
    Local oMemLog
    Local cTexto := ""
    Local nI     := 0
    Local nQtd   := 0

    // Em cargas grandes o log tem uma linha por produto. Jogar tudo no memo
    // trava a tela, entao a exibicao e limitada - o arquivo .log tem o total
    For nI := 1 To Len(aLog)
        If nQtd >= IMP_MAXLOG
            cTexto += CRLF + Replicate("-", 60) + CRLF + ;
                      "... exibicao limitada a " + cValToChar(IMP_MAXLOG) + " linhas. " + ;
                      "Consulte o arquivo de log para o detalhamento completo." + CRLF
            Exit
        EndIf
        cTexto += aLog[nI] + CRLF
        nQtd++
    Next nI

    DEFINE MSDIALOG oDlg TITLE "Resultado da Importacao de Produtos" ;
           FROM 0, 0 TO 430, 800 PIXEL

    @ 006, 005 SAY "Resumo:" SIZE 100, 08 PIXEL OF oDlg
    @ 016, 005 GET oMemRes VAR cResumo MEMO SIZE 385, 062 PIXEL OF oDlg
    oMemRes:lReadOnly := .T.

    @ 084, 005 SAY "Detalhamento linha a linha:" SIZE 150, 08 PIXEL OF oDlg
    @ 094, 005 GET oMemLog VAR cTexto MEMO SIZE 385, 100 PIXEL OF oDlg
    oMemLog:lReadOnly := .T.

    TButton():New(199, 340, "Fechar", oDlg, {|| oDlg:End() }, ;
                  050, 013, , , .F., .T., .F., , .F., , , .F.)

    ACTIVATE MSDIALOG oDlg CENTERED

Return Nil


// ===========================================================================
// PROCESSAMENTO
// ===========================================================================

/*/{Protheus.doc} IP01Proc
Nucleo da rotina: le o arquivo, monta os registros e chama o ExecAuto.

@param aCfg  Array de configuracao (defines CFG_*)
@return aRes Array de resultado (defines RES_*)
/*/
Static Function IP01Proc(aCfg)

    Local aArea    := FWGetArea()
    Local aRes     := Array(RES_SIZE)
    Local aLinhas  := {}
    Local aDicio   := {}
    Local aMapa    := {}
    Local aCampos  := {}
    Local aRetLin  := {}

    Local cLinha   := ""
    Local cSepar   := ""
    Local cErro    := ""
    Local cCodProd := ""

    // Codigos ja lidos, concatenados entre pipes. A busca com $ e nativa e
    // evita o aScan com codeblock, que fica O(n2) em arquivos grandes
    Local cCodArq  := "|"

    Local nI       := 0
    Local nPos     := 0
    Local nOpcAuto := 0
    Local nIniDado := 1
    Local nTotal   := 0
    Local nTamCod  := TamSX3("B1_COD")[1]

    Local lExiste  := .F.

    aRes[RES_LIDAS]  := 0
    aRes[RES_INCLUI] := 0
    aRes[RES_ALTERA] := 0
    aRes[RES_IGNORA] := 0
    aRes[RES_ERRO]   := 0
    aRes[RES_LOG]    := {}
    aRes[RES_REJEIT] := {}

    aAdd(aRes[RES_LOG], Replicate("=", 100))
    aAdd(aRes[RES_LOG], "IMPPRD01 v" + IMP_VERSAO + " - Importacao de Produtos via ExecAuto (MATA010)")
    aAdd(aRes[RES_LOG], "Inicio ...: " + DToC(Date()) + " " + Time())
    aAdd(aRes[RES_LOG], "Arquivo ..: " + aCfg[CFG_ARQUIVO])
    aAdd(aRes[RES_LOG], "Empresa ..: " + FWCodEmp() + " / Filial: " + FWCodFil())
    aAdd(aRes[RES_LOG], "Usuario ..: " + AllTrim(cUserName))
    aAdd(aRes[RES_LOG], "Modo .....: " + IIf(aCfg[CFG_SIMULA], "SIMULACAO (nao grava)", "GRAVACAO"))
    aAdd(aRes[RES_LOG], "Atualizar : " + IIf(aCfg[CFG_ATUALIZ], "SIM", "NAO"))
    aAdd(aRes[RES_LOG], Replicate("=", 100))

    // ----------------------------------------------------------------- leitura
    aLinhas := IP01LerArq(aCfg, @cErro)

    If !Empty(cErro)
        aAdd(aRes[RES_LOG], "ERRO FATAL: " + cErro)
        MsgStop(cErro, "Erro na leitura do arquivo")
        FWRestArea(aArea)
        Return aRes
    EndIf

    If Len(aLinhas) == 0
        aAdd(aRes[RES_LOG], "ERRO FATAL: o arquivo esta vazio.")
        MsgStop("O arquivo esta vazio.", "Atencao")
        FWRestArea(aArea)
        Return aRes
    EndIf

    // --------------------------------------------------------------- separador
    cSepar := IP01Separ(aCfg[CFG_SEPAR], aLinhas[1])

    // --------------------------------------- dicionario dos campos SB1/SB5 (X3)
    aDicio := IP01Dicio()

    // ------------------------------------------------------------ mapa colunas
    If aCfg[CFG_HEADER]
        aMapa    := IP01Mapa(aLinhas[1], cSepar, aDicio, @cErro)
        nIniDado := 2
    Else
        aMapa    := IP01MapFix(aDicio, @cErro)
        nIniDado := 1
    EndIf

    If !Empty(cErro)
        aAdd(aRes[RES_LOG], "ERRO FATAL NO LAYOUT: " + cErro)
        MsgStop(cErro, "Erro no layout do arquivo")
        FWRestArea(aArea)
        Return aRes
    EndIf

    aAdd(aRes[RES_LOG], "Separador : " + IIf(cSepar == IMP_TAB, "<TAB>", cSepar) + ;
                        "   |   Colunas mapeadas: " + cValToChar(Len(aMapa)))
    aAdd(aRes[RES_LOG], "Tabelas ..: SB1 = " + cValToChar(IP01CntTab(aMapa, "SB1")) + ;
                        " campo(s)   |   SB5 (complemento) = " + ;
                        cValToChar(IP01CntTab(aMapa, "SB5")) + " campo(s)")
    aAdd(aRes[RES_LOG], "Campos ...: " + IP01LstCpo(aMapa))
    aAdd(aRes[RES_LOG], Replicate("-", 100))

    nTotal := Len(aLinhas) - (nIniDado - 1)

    ProcRegua(nTotal)

    DbSelectArea("SB1")
    SB1->(DbSetOrder(1))    // B1_FILIAL + B1_COD

    // ---------------------------------------------------------- linha a linha
    For nI := nIniDado To Len(aLinhas)

        cLinha := aLinhas[nI]

        IncProc("Processando linha " + cValToChar(nI) + " de " + cValToChar(Len(aLinhas)) + "...")

        // Despreza linhas em branco ou compostas apenas por separadores
        If Empty(AllTrim(StrTran(cLinha, cSepar, "")))
            Loop
        EndIf

        aRes[RES_LIDAS]++

        // Monta o array de campos no formato esperado pelo ExecAuto
        cErro   := ""
        aCampos := IP01Reg(cLinha, cSepar, aMapa, @cErro)

        If !Empty(cErro)
            aRes[RES_ERRO]++
            aAdd(aRes[RES_LOG], "Linha " + StrZero(nI, 6) + " REJEITADA (layout) : " + cErro)
            aAdd(aRes[RES_REJEIT], {nI, cLinha, cErro})
            Loop
        EndIf

        // O codigo do produto define se e inclusao ou alteracao
        nPos := aScan(aCampos, {|x| AllTrim(Upper(x[1])) == "B1_COD"})

        If nPos == 0 .Or. Empty(aCampos[nPos][2])
            aRes[RES_ERRO]++
            cErro := "Campo B1_COD nao informado."
            aAdd(aRes[RES_LOG], "Linha " + StrZero(nI, 6) + " REJEITADA .......: " + cErro)
            aAdd(aRes[RES_REJEIT], {nI, cLinha, cErro})
            Loop
        EndIf

        cCodProd := PadR(aCampos[nPos][2], nTamCod)

        // Duplicidade dentro do proprio arquivo
        If ("|" + AllTrim(cCodProd) + "|") $ cCodArq
            aRes[RES_ERRO]++
            cErro := "Codigo " + AllTrim(cCodProd) + " duplicado dentro do arquivo."
            aAdd(aRes[RES_LOG], "Linha " + StrZero(nI, 6) + " REJEITADA .......: " + cErro)
            aAdd(aRes[RES_REJEIT], {nI, cLinha, cErro})
            Loop
        EndIf
        cCodArq += AllTrim(cCodProd) + "|"

        lExiste := SB1->(DbSeek(xFilial("SB1") + cCodProd))

        If lExiste .And. !aCfg[CFG_ATUALIZ]
            aRes[RES_IGNORA]++
            aAdd(aRes[RES_LOG], "Linha " + StrZero(nI, 6) + " IGNORADA ........: produto " + ;
                                AllTrim(cCodProd) + " ja cadastrado.")
            Loop
        EndIf

        nOpcAuto := IIf(lExiste, 4, 3)    // 3 = Inclusao / 4 = Alteracao

        // Simulacao: valida o layout e nao chama o ExecAuto
        If aCfg[CFG_SIMULA]
            If nOpcAuto == 3
                aRes[RES_INCLUI]++
            Else
                aRes[RES_ALTERA]++
            EndIf
            aAdd(aRes[RES_LOG], "Linha " + StrZero(nI, 6) + " OK (simulacao) ..: produto " + ;
                                AllTrim(cCodProd) + " seria " + ;
                                IIf(nOpcAuto == 3, "INCLUIDO", "ALTERADO") + ".")
            Loop
        EndIf

        // ------------------------------------------------------------ ExecAuto
        aRetLin := IP01Exec(aCampos, nOpcAuto, cCodProd)

        If aRetLin[1]
            If nOpcAuto == 3
                aRes[RES_INCLUI]++
                aAdd(aRes[RES_LOG], "Linha " + StrZero(nI, 6) + " INCLUIDO ........: " + AllTrim(cCodProd))
            Else
                aRes[RES_ALTERA]++
                aAdd(aRes[RES_LOG], "Linha " + StrZero(nI, 6) + " ALTERADO ........: " + AllTrim(cCodProd))
            EndIf
        Else
            aRes[RES_ERRO]++
            cErro := aRetLin[2]
            aAdd(aRes[RES_LOG], "Linha " + StrZero(nI, 6) + " REJEITADA .......: " + ;
                                AllTrim(cCodProd) + " -> " + cErro)
            aAdd(aRes[RES_REJEIT], {nI, cLinha, cErro})
        EndIf

    Next nI

    aAdd(aRes[RES_LOG], Replicate("-", 100))
    aAdd(aRes[RES_LOG], "Termino ......: " + DToC(Date()) + " " + Time())
    aAdd(aRes[RES_LOG], "Linhas lidas .: " + cValToChar(aRes[RES_LIDAS]))
    aAdd(aRes[RES_LOG], "Incluidos ....: " + cValToChar(aRes[RES_INCLUI]))
    aAdd(aRes[RES_LOG], "Alterados ....: " + cValToChar(aRes[RES_ALTERA]))
    aAdd(aRes[RES_LOG], "Ignorados ....: " + cValToChar(aRes[RES_IGNORA]))
    aAdd(aRes[RES_LOG], "Rejeitados ...: " + cValToChar(aRes[RES_ERRO]))
    aAdd(aRes[RES_LOG], Replicate("=", 100))

    FWRestArea(aArea)

Return aRes


/*/{Protheus.doc} IP01Exec
Executa o MATA010 via MSExecAuto, capturando o erro sem abrir tela.

Toda a validacao do cadastro de produtos (X3_VALID, gatilhos, consistencias
e pontos de entrada) e executada aqui - este e o motivo de usar ExecAuto.

@param aCampos  Array no formato {{cCampo, xValor, Nil}, ...}
@param nOpcAuto 3 = Inclusao  /  4 = Alteracao
@param cCodProd Codigo do produto (usado para posicionar o SB1 na alteracao)
@return aRet    {lOk, cErro}
/*/
Static Function IP01Exec(aCampos, nOpcAuto, cCodProd)

    Local aRet    := {.T., ""}
    Local cFunOld := FunName()

    Private lMsErroAuto    := .F.
    Private lMsHelpAuto    := .T.
    Private lAutoErrNoFile := .T.

    // Na alteracao o MATA010 exige o SB1 posicionado no registro
    If nOpcAuto == 4
        DbSelectArea("SB1")
        SB1->(DbSetOrder(1))
        If !SB1->(DbSeek(xFilial("SB1") + cCodProd))
            Return {.F., "Produto nao localizado no SB1 para alteracao."}
        EndIf
    EndIf

    SetFunName("MATA010")

    Begin Transaction

        MSExecAuto({|x, y| MATA010(x, y)}, aCampos, nOpcAuto)

        If lMsErroAuto
            DisarmTransaction()
            aRet := {.F., IP01GetErr()}
        EndIf

    End Transaction

    // Devolve a numeracao automatica reservada quando a gravacao falhou
    If !aRet[1]
        RollBackSX8()
    EndIf

    SetFunName(cFunOld)

Return aRet


/*/{Protheus.doc} IP01GetErr
Le o log de erro gerado pelo ExecAuto e devolve em uma unica string.
Usa GetAutoGRLog() para nao abrir a tela do MostraErro, o que travaria a
importacao em lote.

@return cErro Mensagem consolidada
/*/
Static Function IP01GetErr()

    Local aLog  := {}
    Local cErro := ""
    Local cAux  := ""
    Local nI    := 0

    aLog := GetAutoGRLog()

    // Sem log disponivel o retorno pode nao ser array - nao deixa o
    // tratamento de erro derrubar a importacao inteira
    If ValType(aLog) != "A"
        aLog := {}
    EndIf

    For nI := 1 To Len(aLog)
        cAux := AllTrim(aLog[nI])
        cAux := StrTran(cAux, Chr(13), " ")
        cAux := StrTran(cAux, Chr(10), " ")
        cAux := AllTrim(cAux)
        If !Empty(cAux)
            cErro += cAux + " / "
        EndIf
    Next nI

    cErro := AllTrim(cErro)

    If Right(cErro, 1) == "/"
        cErro := AllTrim(SubStr(cErro, 1, Len(cErro) - 1))
    EndIf

    If Empty(cErro)
        cErro := "Erro nao identificado pelo ExecAuto."
    EndIf

Return cErro


// ===========================================================================
// LEITURA E PARSE DO ARQUIVO
// ===========================================================================

/*/{Protheus.doc} IP01LerArq
Le o arquivo texto no servidor e devolve um array com as linhas ja tratadas
quanto a codificacao e BOM.

@param aCfg  Array de configuracao
@param cErro Passado por referencia, recebe a mensagem de erro
@return aLin Array de strings
/*/
Static Function IP01LerArq(aCfg, cErro)

    Local aLin   := {}
    Local oFile
    Local cLinha := ""
    Local cArq   := aCfg[CFG_ARQUIVO]
    Local lPrim  := .T.

    cErro := ""

    If !File(cArq)
        cErro := "Arquivo nao localizado no servidor: " + cArq
        Return aLin
    EndIf

    oFile := FWFileReader():New(cArq)

    If !oFile:Open()
        cErro := "Nao foi possivel abrir o arquivo: " + cArq
        Return aLin
    EndIf

    While !oFile:EoF()

        cLinha := oFile:GetLine()

        // Remove o BOM da primeira linha, quando existir
        If lPrim
            If SubStr(cLinha, 1, 3) == IMP_BOM
                cLinha := SubStr(cLinha, 4)
            EndIf
            lPrim := .F.
        EndIf

        cLinha := StrTran(cLinha, Chr(13), "")
        cLinha := StrTran(cLinha, Chr(10), "")
        cLinha := IP01Codif(cLinha, aCfg[CFG_CODIF])

        aAdd(aLin, cLinha)

    EndDo

    oFile:Close()

    // Elimina as linhas vazias do final do arquivo
    While Len(aLin) > 0 .And. Empty(AllTrim(aLin[Len(aLin)]))
        aSize(aLin, Len(aLin) - 1)
    EndDo

Return aLin


/*/{Protheus.doc} IP01Codif
Ajusta a codificacao da linha lida.

@param cLinha Linha lida do arquivo
@param nCodif 1 = arquivo UTF-8 (converte)
              2 = arquivo ANSI  (nao converte)
              3 = ambiente UTF-8 (converte de ANSI)
@return cRet  Linha convertida
/*/
Static Function IP01Codif(cLinha, nCodif)

    Local cRet := cLinha

    Do Case
        Case nCodif == 1
            cRet := DecodeUTF8(cLinha)
            If Empty(cRet) .And. !Empty(cLinha)
                cRet := cLinha              // nao era UTF-8 valido, mantem original
            EndIf

        Case nCodif == 3
            cRet := EncodeUTF8(cLinha)
            If Empty(cRet) .And. !Empty(cLinha)
                cRet := cLinha
            EndIf

        Otherwise
            cRet := cLinha                  // nCodif = 2, sem conversao
    EndCase

Return cRet


/*/{Protheus.doc} IP01Separ
Define o caractere separador. Quando nTipo = 0, detecta automaticamente
a partir da primeira linha do arquivo.

@param nTipo  0=auto  1=";"  2="|"  3=TAB  4=","
@param cLinha Primeira linha do arquivo
@return cSep  Caractere separador
/*/
Static Function IP01Separ(nTipo, cLinha)

    Local cSep := ";"

    Do Case
        Case nTipo == 1 ; cSep := ";"
        Case nTipo == 2 ; cSep := "|"
        Case nTipo == 3 ; cSep := IMP_TAB
        Case nTipo == 4 ; cSep := ","
        Otherwise
            // Detecao automatica pela ocorrencia na primeira linha
            Do Case
                Case IP01Conta(cLinha, ";")     > 0 ; cSep := ";"
                Case IP01Conta(cLinha, "|")     > 0 ; cSep := "|"
                Case IP01Conta(cLinha, IMP_TAB) > 0 ; cSep := IMP_TAB
                Case IP01Conta(cLinha, ",")     > 0 ; cSep := ","
                Otherwise                           ; cSep := ";"
            EndCase
    EndCase

Return cSep


/*/{Protheus.doc} IP01Conta
Conta quantas vezes um caractere aparece dentro de uma string.
/*/
Static Function IP01Conta(cTexto, cChar)
Return Len(cTexto) - Len(StrTran(cTexto, cChar, ""))


/*/{Protheus.doc} IP01Mapa
Monta o mapa de colunas a partir da linha de cabecalho do arquivo.
Aceita tanto o nome tecnico do campo (B1_DESC) quanto o titulo do
dicionario (Descricao).

@param cHeader Linha de cabecalho
@param cSepar  Separador
@param aDicio  Dicionario montado por IP01Dicio()
@param cErro   Por referencia
@return aMapa  Array de {nColuna, cCampo, cTipo, nTam, nDec}
/*/
Static Function IP01Mapa(cHeader, cSepar, aDicio, cErro)

    Local aMapa := {}
    Local aCols := {}
    Local aIgn  := IP01Ignora()
    Local cCol  := ""
    Local nI    := 0
    Local nPos  := 0

    cErro := ""
    aCols := IP01Split(cHeader, cSepar)

    For nI := 1 To Len(aCols)

        cCol := Upper(AllTrim(aCols[nI]))

        If Empty(cCol) .Or. aScan(aIgn, {|x| x == cCol}) > 0
            Loop
        EndIf

        // 1) tenta pelo nome tecnico do campo
        nPos := aScan(aDicio, {|x| x[DIC_CAMPO] == cCol})

        // 2) tenta pelo titulo do dicionario
        If nPos == 0
            nPos := aScan(aDicio, {|x| Upper(AllTrim(x[DIC_TITULO])) == cCol})
        EndIf

        If nPos == 0
            If IP01CpoBlq(cCol)
                cErro := "Coluna " + cValToChar(nI) + " (" + cCol + "): campo de controle nao " + ;
                         "pode ser importado. A filial e definida pelo ambiente. " + ;
                         "Remova essa coluna do arquivo."
            Else
                cErro := "Coluna " + cValToChar(nI) + " (" + cCol + ") nao corresponde a nenhum " + ;
                         "campo real das tabelas SB1/SB5 (campos virtuais nao sao aceitos). " + ;
                         "Corrija o cabecalho do arquivo."
            EndIf
            Return aMapa
        EndIf

        // Evita mapear o mesmo campo duas vezes
        If aScan(aMapa, {|x| x[MAP_CAMPO] == aDicio[nPos][DIC_CAMPO]}) > 0
            cErro := "O campo " + aDicio[nPos][DIC_CAMPO] + " aparece mais de uma vez no cabecalho."
            Return aMapa
        EndIf

        aAdd(aMapa, {nI                        , ;
                     aDicio[nPos][DIC_CAMPO]   , ;
                     aDicio[nPos][DIC_TIPO]    , ;
                     aDicio[nPos][DIC_TAM]     , ;
                     aDicio[nPos][DIC_DEC]     , ;
                     aDicio[nPos][DIC_ARQUIVO] })

    Next nI

    If Len(aMapa) == 0
        cErro := "Nenhuma coluna valida foi encontrada no cabecalho do arquivo."
    ElseIf aScan(aMapa, {|x| x[MAP_CAMPO] == "B1_COD"}) == 0
        cErro := "A coluna B1_COD (codigo do produto) e obrigatoria no arquivo."
    EndIf

Return aMapa


/*/{Protheus.doc} IP01MapFix
Monta o mapa de colunas a partir do layout fixo definido em IP01Layout().

@param aDicio Dicionario montado por IP01Dicio()
@param cErro  Por referencia
@return aMapa Array de {nColuna, cCampo, cTipo, nTam, nDec}
/*/
Static Function IP01MapFix(aDicio, cErro)

    Local aMapa := {}
    Local aLay  := IP01Layout()
    Local cCpo  := ""
    Local nI    := 0
    Local nPos  := 0

    cErro := ""

    For nI := 1 To Len(aLay)

        cCpo := Upper(AllTrim(aLay[nI][1]))
        nPos := aScan(aDicio, {|x| x[DIC_CAMPO] == cCpo})

        If nPos == 0
            cErro := "O campo " + cCpo + " informado em IP01Layout() nao existe no " + ;
                     "dicionario (SX3) das tabelas SB1/SB5."
            Return aMapa
        EndIf

        aAdd(aMapa, {nI                        , ;
                     aDicio[nPos][DIC_CAMPO]   , ;
                     aDicio[nPos][DIC_TIPO]    , ;
                     aDicio[nPos][DIC_TAM]     , ;
                     aDicio[nPos][DIC_DEC]     , ;
                     aDicio[nPos][DIC_ARQUIVO] })

    Next nI

    If aScan(aMapa, {|x| x[MAP_CAMPO] == "B1_COD"}) == 0
        cErro := "O campo B1_COD e obrigatorio no layout definido em IP01Layout()."
    EndIf

Return aMapa


/*/{Protheus.doc} IP01Reg
Converte uma linha do arquivo no array de campos esperado pelo ExecAuto.

Colunas vazias sao omitidas do array, para que o MATA010 aplique o valor
padrao do dicionario (X3_RELACAO) na inclusao e preserve o conteudo atual
na alteracao.

@param cLinha Linha de dados
@param cSepar Separador
@param aMapa  Mapa de colunas
@param cErro  Por referencia
@return aCpo  Array {{cCampo, xValor, Nil}, ...}
/*/
Static Function IP01Reg(cLinha, cSepar, aMapa, cErro)

    Local aCpo   := {}
    Local aCols  := {}
    Local aFixos := IP01Fixos()
    Local cCampo := ""
    Local cValor := ""
    Local xValor
    Local nI     := 0
    Local nCol   := 0

    cErro := ""
    aCols := IP01Split(cLinha, cSepar)

    For nI := 1 To Len(aMapa)

        nCol   := aMapa[nI][MAP_COLUNA]
        cCampo := aMapa[nI][MAP_CAMPO]

        If nCol > Len(aCols)
            Loop                        // coluna ausente nesta linha
        EndIf

        cValor := AllTrim(aCols[nCol])

        If Empty(cValor)
            Loop                        // deixa o ExecAuto aplicar o padrao
        EndIf

        xValor := IP01Conv(cValor           , ;
                           aMapa[nI][MAP_TIPO], ;
                           aMapa[nI][MAP_TAM] , ;
                           aMapa[nI][MAP_DEC] , ;
                           cCampo           , ;
                           @cErro)

        If !Empty(cErro)
            Return aCpo
        EndIf

        aAdd(aCpo, {cCampo, xValor, Nil})

    Next nI

    // Valores fixos - so entram quando a coluna nao veio preenchida no arquivo
    For nI := 1 To Len(aFixos)
        If aScan(aCpo, {|x| AllTrim(Upper(x[1])) == AllTrim(Upper(aFixos[nI][1]))}) == 0
            aAdd(aCpo, {aFixos[nI][1], aFixos[nI][2], Nil})
        EndIf
    Next nI

Return aCpo


/*/{Protheus.doc} IP01Conv
Converte o conteudo lido do arquivo para o tipo do campo no dicionario.

@param cValor Conteudo lido
@param cTipo  X3_TIPO
@param nTam   X3_TAMANHO
@param nDec   X3_DECIMAL
@param cCampo Nome do campo (usado na mensagem de erro)
@param cErro  Por referencia
@return xRet  Valor ja convertido
/*/
Static Function IP01Conv(cValor, cTipo, nTam, nDec, cCampo, cErro)

    Local xRet := Nil
    Local cAux := AllTrim(cValor)

    cErro := ""

    Do Case

        Case cTipo == "C"
            If Len(cAux) > nTam
                cErro := "Campo " + cCampo + ": conteudo com " + cValToChar(Len(cAux)) + ;
                         " caracteres excede o tamanho do dicionario (" + cValToChar(nTam) + ;
                         ") -> '" + cAux + "'"
                Return Nil
            EndIf
            xRet := cAux

        Case cTipo == "M"
            xRet := cAux            // memo nao tem limite fixo de tamanho

        Case cTipo == "N"
            xRet := IP01Num(cAux, @cErro)
            If !Empty(cErro)
                cErro := "Campo " + cCampo + ": " + cErro
                Return Nil
            EndIf
            xRet := Round(xRet, nDec)

        Case cTipo == "D"
            xRet := IP01Data(cAux, @cErro)
            If !Empty(cErro)
                cErro := "Campo " + cCampo + ": " + cErro
                Return Nil
            EndIf

        Case cTipo == "L"
            xRet := (Upper(cAux) $ "1/S/SIM/T/.T./TRUE/V/VERDADEIRO")

        Otherwise
            cErro := "Campo " + cCampo + ": tipo '" + cTipo + "' nao tratado pela rotina."
            Return Nil

    EndCase

Return xRet


/*/{Protheus.doc} IP01Num
Converte texto em numero aceitando os formatos brasileiro (1.234,56) e
americano (1234.56).

@param cValor Texto
@param cErro  Por referencia
@return nRet  Numero convertido
/*/
Static Function IP01Num(cValor, cErro)

    Local cAux    := AllTrim(cValor)
    Local cLimpo  := ""
    Local cChar   := ""
    Local nRet    := 0
    Local nPtoPos := 0
    Local nVirPos := 0
    Local nI      := 0

    cErro := ""

    // Mantem apenas digitos, separadores e sinal; descarta simbolos de planilha
    For nI := 1 To Len(cAux)
        cChar := SubStr(cAux, nI, 1)
        Do Case
            Case cChar $ "0123456789.,-+"
                cLimpo += cChar
            Case cChar $ " R$%"
                // simbolos comuns em exportacoes: apenas ignora
            Otherwise
                cErro := "valor numerico invalido -> '" + cAux + "'"
                Return 0
        EndCase
    Next nI

    If Empty(cLimpo)
        Return 0
    EndIf

    nPtoPos := RAt(".", cLimpo)
    nVirPos := RAt(",", cLimpo)

    Do Case
        Case nPtoPos > 0 .And. nVirPos > 0
            // O separador mais a direita e o decimal
            If nVirPos > nPtoPos
                cLimpo := StrTran(cLimpo, ".", "")
                cLimpo := StrTran(cLimpo, ",", ".")
            Else
                cLimpo := StrTran(cLimpo, ",", "")
            EndIf

        Case nVirPos > 0
            // Somente virgula: separador decimal (padrao brasileiro)
            cLimpo := StrTran(cLimpo, ",", ".")

        Case nPtoPos > 0
            // Somente ponto: decimal. Mais de um ponto = separador de milhar
            If IP01Conta(cLimpo, ".") > 1
                cLimpo := StrTran(cLimpo, ".", "")
            EndIf
    EndCase

    nRet := Val(cLimpo)

Return nRet


/*/{Protheus.doc} IP01Data
Converte texto em data aceitando DD/MM/AAAA, DD-MM-AAAA, AAAAMMDD e AAAA-MM-DD.

@param cValor Texto
@param cErro  Por referencia
@return dRet  Data convertida
/*/
Static Function IP01Data(cValor, cErro)

    Local cAux := AllTrim(cValor)
    Local dRet := CToD("")

    cErro := ""

    cAux := StrTran(cAux, "-", "/")
    cAux := StrTran(cAux, ".", "/")

    Do Case
        Case Len(cAux) == 8 .And. !("/" $ cAux)
            dRet := SToD(cAux)                        // AAAAMMDD

        Case Len(cAux) == 10 .And. SubStr(cAux, 5, 1) == "/"
            dRet := SToD(StrTran(cAux, "/", ""))      // AAAA/MM/DD

        Case "/" $ cAux
            dRet := CToD(cAux)                        // DD/MM/AAAA (conforme SET DATE)

        Otherwise
            cErro := "data invalida -> '" + cValor + "'"
            Return CToD("")
    EndCase

    If Empty(dRet)
        cErro := "data invalida -> '" + cValor + "'"
    EndIf

Return dRet


/*/{Protheus.doc} IP01Split
Quebra uma linha em array pelo separador informado, respeitando o conteudo
entre aspas duplas (padrao CSV). Assim uma descricao como
"CABO 2,5MM; AZUL" nao e quebrada indevidamente.

Colunas vazias consecutivas sao preservadas, por isso nao se usa StrTokArray.

@param cTexto Linha do arquivo
@param cSepar Separador (1 caractere)
@return aRet  Array de strings
/*/
Static Function IP01Split(cTexto, cSepar)

    Local aRet   := {}
    Local cCampo := ""
    Local cChar  := ""
    Local lAspas := .F.
    Local nI     := 1
    Local nTam   := Len(cTexto)

    While nI <= nTam

        cChar := SubStr(cTexto, nI, 1)

        If cChar == IMP_ASPA .And. lAspas .And. SubStr(cTexto, nI + 1, 1) == IMP_ASPA
            // Aspas duplicadas dentro do campo representam uma aspa literal
            cCampo += IMP_ASPA
            nI += 2

        ElseIf cChar == IMP_ASPA
            lAspas := !lAspas
            nI++

        ElseIf cChar == cSepar .And. !lAspas
            aAdd(aRet, cCampo)
            cCampo := ""
            nI++

        Else
            cCampo += cChar
            nI++

        EndIf

    EndDo

    aAdd(aRet, cCampo)

Return aRet


// ===========================================================================
// DICIONARIO
// ===========================================================================

/*/{Protheus.doc} IP01Dicio
Monta em memoria o dicionario dos campos das tabelas SB1 e SB5, evitando
consultar o SX3 a cada linha do arquivo.

O MATA010 grava o complemento do produto (SB5) a partir do mesmo array de
campos, por isso as duas tabelas sao carregadas.

Campos VIRTUAIS (X3_CONTEXT = "V") sao descartados: nao existem fisicamente
na tabela, nao podem ser enviados ao ExecAuto e costumam repetir o titulo de
um campo real, o que faria a busca por titulo casar com o campo errado.

@return aDic Array de {cCampo, cTipo, nTam, nDec, cTitulo, cArquivo}
/*/
Static Function IP01Dicio()

    Local aDic  := {}
    Local aArqs := {"SB1", "SB5"}
    Local aArea := SX3->(GetArea())
    Local nOrd  := SX3->(IndexOrd())
    Local nI    := 0

    SX3->(DbSetOrder(1))    // X3_ARQUIVO

    For nI := 1 To Len(aArqs)

        If SX3->(DbSeek(aArqs[nI]))
            While !SX3->(Eof()) .And. AllTrim(SX3->X3_ARQUIVO) == aArqs[nI]

                If AllTrim(SX3->X3_CONTEXT) == "V" .Or. IP01CpoBlq(AllTrim(SX3->X3_CAMPO))
                    SX3->(DbSkip())
                    Loop
                EndIf

                aAdd(aDic, {AllTrim(SX3->X3_CAMPO)  , ;
                            AllTrim(SX3->X3_TIPO)   , ;
                            SX3->X3_TAMANHO         , ;
                            SX3->X3_DECIMAL         , ;
                            AllTrim(X3Titulo())     , ;
                            AllTrim(SX3->X3_ARQUIVO)})
                SX3->(DbSkip())
            EndDo
        EndIf

    Next nI

    SX3->(DbSetOrder(nOrd))
    SX3->(RestArea(aArea))

Return aDic


/*/{Protheus.doc} IP01CpoBlq
Indica se o campo e de controle e nao pode ser alimentado pela importacao.

A filial e definida pelo ambiente (xFilial) e os campos de controle sao
gerenciados pelo banco - enviar qualquer um deles ao ExecAuto provoca
comportamento imprevisivel na gravacao.

@param cCampo Nome do campo
@return lBlq  .T. quando o campo e bloqueado
/*/
Static Function IP01CpoBlq(cCampo)

    Local cAux := AllTrim(Upper(cCampo))

Return Right(cAux, 7) == "_FILIAL" .Or. ;
       cAux $ "D_E_L_E_T_/R_E_C_N_O_/R_E_C_D_E_L_"


/*/{Protheus.doc} IP01LstCpo
Devolve a lista dos campos mapeados, separada por virgula, para o log.
/*/
Static Function IP01LstCpo(aMapa)

    Local cRet := ""
    Local nI   := 0

    For nI := 1 To Len(aMapa)
        cRet += aMapa[nI][MAP_CAMPO] + IIf(nI < Len(aMapa), ", ", "")
    Next nI

Return cRet


/*/{Protheus.doc} IP01CntTab
Conta quantos campos do mapa pertencem a tabela informada.
Serve para o log evidenciar quando o arquivo alimenta o complemento (SB5).

@param aMapa Mapa de colunas
@param cTab  Tabela ("SB1" ou "SB5")
@return nRet Quantidade de campos
/*/
Static Function IP01CntTab(aMapa, cTab)

    Local nRet := 0
    Local nI   := 0

    For nI := 1 To Len(aMapa)
        If aMapa[nI][MAP_ARQUIVO] == cTab
            nRet++
        EndIf
    Next nI

Return nRet


// ===========================================================================
// LOG, REJEITADOS E ARQUIVO MODELO
// ===========================================================================

/*/{Protheus.doc} IP01GrvLog
Grava o log detalhado da importacao em arquivo texto no servidor.

@return cArq Caminho do arquivo gerado ("" em caso de falha)
/*/
Static Function IP01GrvLog(aCfg, aRes)

    Local cDir := aCfg[CFG_DIRLOG]
    Local cArq := ""
    Local nHdl := 0
    Local nI   := 0

    If Right(cDir, 1) != "\"
        cDir += "\"
    EndIf

    IP01MkDir(cDir)

    cArq := cDir + "IMPPRD01_" + DToS(Date()) + "_" + StrTran(Time(), ":", "") + ".log"
    nHdl := FCreate(cArq)

    If nHdl == -1
        ConOut("[IMPPRD01] Nao foi possivel criar o log: " + cArq + ;
               " (FError " + cValToChar(FError()) + ")")
        Return ""
    EndIf

    For nI := 1 To Len(aRes[RES_LOG])
        FWrite(nHdl, aRes[RES_LOG][nI] + CRLF)
    Next nI

    FClose(nHdl)

Return cArq


/*/{Protheus.doc} IP01GrvRej
Gera um CSV com as linhas rejeitadas e o motivo de cada uma, pronto para o
usuario corrigir e reimportar apenas o que falhou.

@return cArq Caminho do arquivo gerado ("" quando nao houve rejeicao)
/*/
Static Function IP01GrvRej(aCfg, aRes)

    Local cDir := aCfg[CFG_DIRLOG]
    Local cArq := ""
    Local nHdl := 0
    Local nI   := 0

    If Len(aRes[RES_REJEIT]) == 0
        Return ""
    EndIf

    If Right(cDir, 1) != "\"
        cDir += "\"
    EndIf

    IP01MkDir(cDir)

    cArq := cDir + "REJEITADOS_" + DToS(Date()) + "_" + StrTran(Time(), ":", "") + ".csv"
    nHdl := FCreate(cArq)

    If nHdl == -1
        Return ""
    EndIf

    FWrite(nHdl, "LINHA;CONTEUDO_ORIGINAL;MOTIVO" + CRLF)

    For nI := 1 To Len(aRes[RES_REJEIT])
        FWrite(nHdl, cValToChar(aRes[RES_REJEIT][nI][1]) + ";" + ;
                     IMP_ASPA + StrTran(aRes[RES_REJEIT][nI][2], IMP_ASPA, "") + IMP_ASPA + ";" + ;
                     IMP_ASPA + StrTran(aRes[RES_REJEIT][nI][3], IMP_ASPA, "") + IMP_ASPA + CRLF)
    Next nI

    FClose(nHdl)

Return cArq


/*/{Protheus.doc} IP01Modelo
Gera no servidor um arquivo CSV modelo, com o cabecalho montado a partir do
layout de IP01Layout() e com os titulos do dicionario como referencia.
/*/
Static Function IP01Modelo()

    Local aLay   := IP01Layout()
    Local aDicio := IP01Dicio()
    Local cArq   := IMP_DIRPAD + "MODELO_PRODUTOS.csv"
    Local cHead  := ""
    Local cTitu  := ""
    Local nHdl   := 0
    Local nI     := 0
    Local nPos   := 0

    IP01MkDir(IMP_DIRPAD)

    For nI := 1 To Len(aLay)
        cHead += aLay[nI][1] + IIf(nI < Len(aLay), ";", "")
        nPos  := aScan(aDicio, {|x| x[DIC_CAMPO] == Upper(AllTrim(aLay[nI][1]))})
        cTitu += IIf(nPos > 0, aDicio[nPos][DIC_TITULO], aLay[nI][2]) + ;
                 IIf(nI < Len(aLay), ";", "")
    Next nI

    nHdl := FCreate(cArq)

    If nHdl == -1
        MsgStop("Nao foi possivel gravar o arquivo modelo em:" + CRLF + cArq, "Atencao")
        Return Nil
    EndIf

    FWrite(nHdl, cHead + CRLF)
    FClose(nHdl)

    MsgInfo("Arquivo modelo gerado no servidor:" + CRLF + CRLF + cArq + CRLF + CRLF + ;
            "Cabecalho tecnico:" + CRLF + cHead + CRLF + CRLF + ;
            "Titulos correspondentes:" + CRLF + cTitu, "Modelo gerado")

Return Nil


/*/{Protheus.doc} IP01MkDir
Cria o diretorio no servidor quando ele ainda nao existe.
/*/
Static Function IP01MkDir(cDir)

    Local cAux := AllTrim(cDir)

    If Right(cAux, 1) != "\"
        cAux += "\"
    EndIf

    If !ExistDir(cAux)
        MakeDir(cAux)
    EndIf

Return Nil


/*/{Protheus.doc} IP01NmArq
Extrai apenas o nome do arquivo a partir de um caminho completo.
/*/
Static Function IP01NmArq(cCaminho)

    Local cRet := AllTrim(cCaminho)
    Local nPos := 0

    cRet := StrTran(cRet, "/", "\")
    nPos := RAt("\", cRet)

    If nPos > 0
        cRet := SubStr(cRet, nPos + 1)
    EndIf

Return cRet
