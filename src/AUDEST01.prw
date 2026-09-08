#Include "Protheus.ch"
#Include "FileIO.ch"
#Include "TopConn.ch"
#Include "TBIConn.ch"

/* ===========================================================================
   zAudEst - Auditoria de Roteiro / Estrutura (SB1 x SG1 x SG2)

   Compativel com Protheus 12.1.2410 / SmartClient HTML (navegador).

   A rotina explode a estrutura do item informado (CTE recursiva no SQL
   Server), classifica cada componente e gera um relatorio HTML no mesmo
   padrao visual do documento de auditoria usado pela engenharia.

   SOMENTE LEITURA: nao existe nenhum INSERT/UPDATE/DELETE nem gravacao em
   tabela do Protheus. O unico efeito colateral e a criacao dos arquivos de
   saida (HTML e CSV) na pasta de relatorios.

   PONTOS DE MANUTENCAO (unicos lugares que normalmente precisam ser alterados):
      AE01Chapas() ... 15 codigos de chapa e o peso de uma chapa 3000x1200
      AE01Regras() ... por tipo: quando exige roteiro e quando e folha valida
      AE01Criter() ... textos do quadro "CRITERIOS DE ANALISE" do relatorio

   ONDE FICA A REGRA (mapa da query original)
   ------------------------------------------------------------------------
   A CTE recursiva, os filtros de vigencia (G1_INI/G1_FIM), de revisao
   (G1_REVINI/G1_REVFIM) e os EXISTS de SG1/SG2 continuam no SQL, iguais a
   query validada pela engenharia - ver AE01Sql().

   Sairam do SQL para o ADVPL apenas tres coisas, sem mudanca de resultado:

      TemFilho ... no SQL era um EXISTS contra a propria CTE recursiva. O SQL
                   Server reexecuta a recursao inteira a cada linha, o que em
                   arvores grandes (1.700+ linhas) deixa a consulta inviavel
                   dentro do SmartClient. Em ADVPL e a mesma informacao:
                   "este codigo aparece como pai em alguma linha do retorno".

      Situacao ... os dois CASE gigantes foram transcritos em AE01Class(), na
      Motivo       mesma ordem de avaliacao do original (as clausulas estao
                   numeradas nos comentarios). Manter a ordem e obrigatorio:
                   ela e que define qual motivo prevalece quando o mesmo
                   componente tem mais de um problema.

   O relatorio precisa separar erro de ESTRUTURA de erro de ROTEIRO em duas
   colunas, e o campo Situacao da query original mostra so o primeiro dos
   dois. Por isso as duas condicoes tambem sao avaliadas de forma isolada,
   em AE01ErrEst() e AE01ErrRot().

   Autor..: Jonas - Analise de Sistemas
   =========================================================================== */

// --- Constantes gerais ------------------------------------------------------
#DEFINE AUD_VERSAO    "1.00"
#DEFINE AUD_DIRPAD    "\aud_estrut\"
#DEFINE AUD_DIRREL    "\aud_estrut\relatorio\"

// Pasta na ESTACAO (maquina do usuario) para onde os arquivos gerados sao
// copiados ao final. FCreate grava no servidor, entao a copia e feita por
// CpyS2T. Deixe vazio para nao copiar.
#DEFINE AUD_DIRESTA   "C:\Erros Protheus"

#DEFINE AUD_FILIAL    "00"      // Filial usada nos filtros de SB1/SG1/SG2
#DEFINE AUD_NIVEL     25        // Profundidade maxima da explosao
#DEFINE AUD_LIMMM     6000      // Limite de quantidade para componentes em MM
#DEFINE AUD_FINAME    "FIN"     // Prefixo do PA Finame (dispensado de roteiro)
#DEFINE AUD_REVPAD    "001"     // Revisao assumida quando B1_REVATU esta vazio
#DEFINE AUD_MAXPAI    6         // Codigos pai listados por erro no relatorio
#DEFINE AUD_MAXARV    3000      // Linhas da arvore no anexo do HTML
#DEFINE AUD_ASPA      Chr(34)
#DEFINE AUD_SEMCAD    "(sem cadastro)"   // Pseudo-tipo do item ausente no SB1

// --- Posicoes do array de configuracao (aCfg) -------------------------------
#DEFINE CFG_PRODUTO   1    // Codigo do item principal
#DEFINE CFG_REVISAO   2    // Revisao consultada (vale so no principal)
#DEFINE CFG_FILIAL    3    // Filial usada nos filtros
#DEFINE CFG_NIVEL     4    // Profundidade maxima da explosao
#DEFINE CFG_ARVORE    5    // .T. = anexa a arvore completa no HTML
#DEFINE CFG_CSV       6    // .T. = gera tambem o CSV analitico
#DEFINE CFG_CODIF     7    // 1 = ANSI (windows-1252)  2 = UTF-8
#DEFINE CFG_DIRREL    8    // Diretorio de saida no servidor
#DEFINE CFG_DIREST    9    // Diretorio de destino na estacao
#DEFINE CFG_SIZE      9

// --- Posicoes de cada linha da explosao (aRes[RES_LINHAS]) ------------------
#DEFINE LIN_NIVEL     1    // Nivel na arvore (0 = item principal)
#DEFINE LIN_CODPAI    2    // Codigo do pai ("" no principal)
#DEFINE LIN_CODIGO    3    // Codigo do componente
#DEFINE LIN_DESC      4    // B1_DESC
#DEFINE LIN_TIPO      5    // B1_TIPO
#DEFINE LIN_UM        6    // B1_UM
#DEFINE LIN_QUANT     7    // G1_QUANT da linha (quantidade naquele pai)
#DEFINE LIN_BLOQ      8    // .T. = B1_MSBLQL = '1'
#DEFINE LIN_TEMEST    9    // .T. = tem estrutura vigente (SG1)
#DEFINE LIN_TEMROT   10    // .T. = tem roteiro (SG2)
#DEFINE LIN_REVATU   11    // B1_REVATU
#DEFINE LIN_REVCON   12    // Revisao usada na explosao dessa linha
#DEFINE LIN_NOSB1    13    // .T. = componente existe no SB1
#DEFINE LIN_CAMINHO  14    // Caminho |pai|filho|... montado na CTE
#DEFINE LIN_TEMFILHO 15    // .T. = aparece como pai em alguma linha (calculado)
#DEFINE LIN_ERREST   16    // .T. = erro de estrutura (calculado)
#DEFINE LIN_ERRROT   17    // .T. = erro de roteiro (calculado)
#DEFINE LIN_SITUACAO 18    // OK / ERRO / VERIFICAR (calculado)
#DEFINE LIN_MOTIVO   19    // Motivo da situacao (calculado)
#DEFINE LIN_ERRQTD   20    // .T. = erro de quantidade ou de cadastro (calculado)
#DEFINE LIN_SIZE     20

// --- Posicoes de cada codigo unico com ocorrencia (ERR_*) -------------------
#DEFINE ERR_CODIGO    1
#DEFINE ERR_DESC      2
#DEFINE ERR_TIPO      3
#DEFINE ERR_OCORR     4    // Quantas vezes aparece na arvore
#DEFINE ERR_EST       5    // "OK" / "ERRO" / "-"
#DEFINE ERR_ROT       6    // "OK" / "ERRO" / "-"
#DEFINE ERR_MOTIVO    7    // Motivos distintos, separados por " | "
#DEFINE ERR_PAIS      8    // Array de codigos pai {cPai, nNivel}
#DEFINE ERR_SIZE      8

// --- Posicoes do resumo por tipo - estrutura (TOT_*) ------------------------
#DEFINE TOT_TIPO      1
#DEFINE TOT_TOTAL     2    // Ocorrencias na arvore completa
#DEFINE TOT_OK        3
#DEFINE TOT_SEMEST    4

// --- Posicoes do resumo por tipo - roteiro (ROT_*) --------------------------
#DEFINE ROT_TIPO      1
#DEFINE ROT_UNICOS    2    // Codigos unicos daquele tipo
#DEFINE ROT_COM       3    // Unicos com roteiro no SG2
#DEFINE ROT_SEM       4    // Unicos sem roteiro
#DEFINE ROT_ERRO      5    // Unicos que exigem roteiro e nao tem
#DEFINE ROT_EXIGE     6    // Texto da coluna "EXIGE?"

// --- Posicoes do cabecalho do relatorio (CAB_*) -----------------------------
#DEFINE CAB_CODIGO    1
#DEFINE CAB_DESC      2
#DEFINE CAB_TIPO      3
#DEFINE CAB_REVISAO   4
#DEFINE CAB_REVATU    5
#DEFINE CAB_FILIAL    6
#DEFINE CAB_SIZE      6

// --- Posicoes do array de resultado (aRes) ----------------------------------
#DEFINE RES_LINHAS    1    // Todas as linhas da explosao (LIN_*)
#DEFINE RES_ERROS     2    // Codigos unicos com ERRO (ERR_*)
#DEFINE RES_ALERTAS   3    // Codigos unicos com VERIFICAR (ERR_*)
#DEFINE RES_TOTEST    4    // Resumo por tipo - estrutura (TOT_*)
#DEFINE RES_TOTROT    5    // Resumo por tipo - roteiro (ROT_*)
#DEFINE RES_CAB       6    // Cabecalho (CAB_*)
#DEFINE RES_QTDEST    7    // Codigos unicos com erro de estrutura
#DEFINE RES_QTDROT    8    // Codigos unicos com erro de roteiro
#DEFINE RES_QTDOUT    9    // Codigos unicos com erro de quantidade/cadastro
#DEFINE RES_SIZE      9

// --- Posicoes da tabela de regras por tipo (REG_*) --------------------------
#DEFINE REG_TIPO      1
#DEFINE REG_EXIGE     2    // Texto exibido na coluna "EXIGE?" (HTML)
#DEFINE REG_SEMPRE    3    // .T. = exige roteiro sempre
#DEFINE REG_SEEST     4    // .T. = exige roteiro so quando tem estrutura
#DEFINE REG_FOLHA     5    // "S" sempre folha / "E" folha sem estrutura / "N" nunca

// --- Paleta do relatorio (mesmas cores do documento modelo) -----------------
#DEFINE COR_TINTA     "#1A1D29"    // Texto principal / barra de secao
#DEFINE COR_SUAVE     "#6B7280"    // Texto secundario
#DEFINE COR_AZUL      "#1F2E99"    // Azul escuro - totais e quadro de estrutura
#DEFINE COR_AZULCLA   "#8FA0FF"    // Numero da secao sobre a barra escura
#DEFINE COR_VERM      "#D6304A"    // Erro
#DEFINE COR_VERDE     "#16924E"    // OK
#DEFINE COR_VERDESC   "#0E6B4C"    // Verde escuro - quadro de roteiro
#DEFINE COR_AMBAR     "#B26A00"    // Verificar
#DEFINE COR_FDVERM    "#FDECEF"
#DEFINE COR_FDVERDE   "#EAFAF1"
#DEFINE COR_FDVERD2   "#E8F5EE"
#DEFINE COR_FDAMBAR   "#FFF6E5"
#DEFINE COR_FDAZUL    "#EEF1FF"
#DEFINE COR_FDAZUL2   "#F4F6FF"
#DEFINE COR_FDCINZA   "#F7F8FA"
#DEFINE COR_BORDA     "#E5E7EB"


/*/{Protheus.doc} zAudEst
Ponto de entrada da rotina. Abre a tela de parametrizacao da auditoria.

Cadastro no menu (SIGAMDI) -> Programa: U_zAudEst / Tipo: Funcao Protheus

@author  Jonas
@since   09/2026
@version 1.00
/*/
User Function zAudEst()

    Local aArea := FWGetArea()

    // Garante os diretorios de trabalho no servidor
    AE01MkDir(AUD_DIRPAD)
    AE01MkDir(AUD_DIRREL)

    AE01Tela()

    FWRestArea(aArea)

Return Nil


// ===========================================================================
// AREA DE MANUTENCAO - normalmente e so aqui que voce precisa mexer
// ===========================================================================

/*/{Protheus.doc} AE01Chapas
Codigos de chapa que possuem teto de consumo e o peso, em KG, de uma chapa
inteira de 3000x1200. Sao as regras 7 da especificacao:

   UM diferente de KG ............................ ERRO
   UM = KG e G1_QUANT maior que o peso da chapa .. ERRO

O teste e linha a linha - vale a quantidade daquela chapa naquele pai, e
nao o acumulado da arvore.

Para incluir uma chapa nova basta acrescentar uma linha aqui - a lista e
lida por AE01Class(), que e quem aplica as duas regras.

Estrutura de cada elemento:
   [1] Codigo do produto (SB1)
   [2] Peso de uma chapa 3000x1200, em KG

@return aChp Array com os codigos e os respectivos tetos
/*/
Static Function AE01Chapas()

    Local aChp := {}

    //         Codigo               Teto (KG)
    aAdd(aChp, {"28CHLQACGNQ4C04",   76.302})
    aAdd(aChp, {"28CHCGACNMQ2E05",  446.508})
    aAdd(aChp, {"28CHLQACGNQ4C03",   55.107})
    aAdd(aChp, {"28CHLFACGNQ4C02",   43.803})
    aAdd(aChp, {"28CHLQACNMQ2B03",  134.235})
    aAdd(aChp, {"28CHCGACNMQ2E02",  224.384})
    aAdd(aChp, {"28CHLQACNMQ2B01",   74.889})
    aAdd(aChp, {"28CHLQACNMQ2B04",   74.889})
    aAdd(aChp, {"28CHCGACNMQ2E01",  179.451})
    aAdd(aChp, {"28CHCGACNMQ2E04",  358.902})
    aAdd(aChp, {"28CHCGACNMQ2E03",  269.318})
    aAdd(aChp, {"28CHLQACNMQ2B02",   94.671})
    aAdd(aChp, {"28CHLFACNMQ2A02",   53.694})
    aAdd(aChp, {"28CHLFACGNQ4C01",   26.847})
    aAdd(aChp, {"28CHLFACNMQ2A01",   42.390})

Return aChp


/*/{Protheus.doc} AE01Regras
Regra de roteiro e de folha valida para cada tipo de produto (B1_TIPO).

A ORDEM DO ARRAY E A ORDEM DAS LINHAS nos quadros "ANALISE DE ESTRUTURA" e
"ANALISE DE ROTEIRO" do relatorio. Tipos encontrados na arvore que nao
estiverem nesta tabela sao acrescentados no final e tratados como PA/PI
(exigem roteiro e nunca sao folha valida), que e o comportamento da query
original para tipos nao previstos.

Estrutura de cada elemento:
   [1] Tipo (B1_TIPO)
   [2] Texto da coluna "EXIGE?" no quadro de roteiro - vai direto para o
       HTML, entao acentos precisam ser escritos como entidade (&aacute;)
   [3] .T. = exige roteiro sempre
   [4] .T. = exige roteiro somente quando tem estrutura vigente
   [5] Folha valida:  "S" sempre / "E" so quando NAO tem estrutura / "N" nunca

O PA cujo codigo comeca com AUD_FINAME ("FIN") e dispensado de roteiro
mesmo com [3] ligado - a excecao Finame esta em AE01ExRot().

@return aReg Array com as regras por tipo
/*/
Static Function AE01Regras()

    Local aReg := {}

    //         Tipo   Texto "EXIGE?"                       Sempre  SeEstrut  Folha
    aAdd(aReg, {"PA", "Sim, exceto " + AUD_FINAME + "*"  , .T.   , .F.     , "N"})
    aAdd(aReg, {"PI", "Sim"                              , .T.   , .F.     , "N"})
    aAdd(aReg, {"EM", "S&oacute; se tiver estrutura"     , .F.   , .T.     , "E"})
    aAdd(aReg, {"MP", "N&atilde;o"                       , .F.   , .F.     , "S"})
    aAdd(aReg, {"BN", "S&oacute; se tiver estrutura"     , .F.   , .T.     , "E"})
    aAdd(aReg, {"SV", "N&atilde;o"                       , .F.   , .F.     , "S"})

Return aReg


/*/{Protheus.doc} AE01Criter
Textos do quadro "CRITERIOS DE ANALISE", impresso no fim do relatorio.

Sao apenas textos - alterar aqui nao muda nenhuma classificacao. Ao mexer
em AE01Regras() ou nos limites (AUD_LIMMM, AUD_FINAME), lembre de refletir
a mudanca nestes textos para o relatorio nao explicar uma regra que a
rotina nao aplica mais.

Vao direto para o HTML: use entidades (&aacute;, &ccedil;) nos acentos.

Estrutura de cada elemento:
   [1] Rotulo em negrito
   [2] Texto da regra

@param cFilial Filial auditada, para o texto da regra de roteiro
@return aCri   Array com os criterios
/*/
Static Function AE01Criter(cFilial)

    Local aCri := {}

    aAdd(aCri, {"PA e PI", ;
                "sempre exigem roteiro, exceto o PA cujo c&oacute;digo come&ccedil;a " + ;
                "com " + AUD_FINAME + " (Finame)."})
    aAdd(aCri, {"EM", ;
                "exige roteiro somente se tiver estrutura; folha (sem SG1) n&atilde;o exige."})
    aAdd(aCri, {"BN", ;
                "exige roteiro somente se tiver estrutura (fabricado); folha comprada " + ;
                "n&atilde;o exige."})
    aAdd(aCri, {"MP e SV", ;
                "n&atilde;o exigem roteiro."})
    aAdd(aCri, {"Roteiro", ;
                "qualquer opera&ccedil;&atilde;o em SG2 na filial " + ;
                AllTrim(cFilial) + ", sem filtro de data."})
    aAdd(aCri, {"Estrutura vigente", ;
                "o item desce at&eacute; uma folha v&aacute;lida na &aacute;rvore; " + ;
                "PA/PI que n&atilde;o descem s&atilde;o marcados como ERRO."})
    aAdd(aCri, {"Chapas", ;
                "os " + cValToChar(Len(AE01Chapas())) + " c&oacute;digos com teto exigem " + ;
                "UM = KG e quantidade at&eacute; o peso de uma chapa 3000x1200."})
    aAdd(aCri, {"Medida linear", ;
                "componente com UM = MM e quantidade acima de " + ;
                cValToChar(AUD_LIMMM) + " &eacute; erro."})

Return aCri


// ===========================================================================
// TELA
// ===========================================================================

/*/{Protheus.doc} AE01Tela
Tela de parametrizacao da auditoria.

Usa apenas componentes suportados no SmartClient HTML (navegador): MSGET,
COMBOBOX, CHECKBOX e TButton. O relatorio nasce no servidor e e copiado
para a estacao por CpyS2T no final.
/*/
Static Function AE01Tela()

    Local oDlg
    Local oFont
    Local oGetPrd
    Local oGetRev
    Local oGetFil
    Local oGetNiv
    Local oGetDir
    Local oGetEst
    Local oCboCod
    Local oChkArv
    Local oChkCsv

    Local nLin     := 0

    Local cProduto := Space(TamSX3("B1_COD")[1])
    Local cRevisao := PadR(AUD_REVPAD, 3)
    Local cFilial  := PadR(AUD_FILIAL, TamSX3("B1_FILIAL")[1])
    Local cDirRel  := PadR(AUD_DIRREL, 250)
    Local cDirEst  := PadR(AUD_DIRESTA, 250)

    Local nNivel   := AUD_NIVEL
    Local nCodif   := 1

    Local lArvore  := .F.
    Local lCsv     := .T.

    Local aCodif   := {"1=ANSI / Windows-1252  (padrao)", ;
                       "2=UTF-8"}

    oFont := TFont():New("Arial", , -12, .T., .T.)

    DEFINE MSDIALOG oDlg TITLE "Auditoria de Roteiro / Estrutura - versao " + AUD_VERSAO ;
           FROM 0, 0 TO 250, 700 PIXEL

    nLin := 8
    @ nLin, 010 SAY "Confere estrutura (SG1) e roteiro (SG2) de toda a arvore do item" ;
                SIZE 320, 10 FONT oFont PIXEL OF oDlg

    nLin += 12
    @ nLin, 010 SAY "Consulta somente leitura - nenhuma tabela do Protheus e alterada." ;
                SIZE 320, 08 PIXEL OF oDlg

    nLin += 20
    @ nLin, 010 SAY "Produto:" SIZE 042, 08 PIXEL OF oDlg
    @ nLin - 1, 055 MSGET oGetPrd VAR cProduto F3 "SB1" SIZE 120, 10 PIXEL OF oDlg ;
                VALID (cRevisao := AE01VldPrd(cProduto, cRevisao), AE01Refr(oGetRev), .T.)

    @ nLin, 190 SAY "Revisao:" SIZE 040, 08 PIXEL OF oDlg
    @ nLin - 1, 232 MSGET oGetRev VAR cRevisao PICTURE "@!" SIZE 030, 10 PIXEL OF oDlg

    @ nLin, 272 SAY "Filial:" SIZE 030, 08 PIXEL OF oDlg
    @ nLin - 1, 297 MSGET oGetFil VAR cFilial PICTURE "@!" SIZE 030, 10 PIXEL OF oDlg

    nLin += 17
    @ nLin, 010 SAY "Nivel maximo:" SIZE 050, 08 PIXEL OF oDlg
    @ nLin - 1, 062 MSGET oGetNiv VAR nNivel PICTURE "@E 99" SIZE 020, 10 PIXEL OF oDlg

    @ nLin, 100 SAY "Profundidade da explosao (MAXRECURSION)." SIZE 160, 08 PIXEL OF oDlg

    @ nLin, 240 SAY "Codificacao:" SIZE 045, 08 PIXEL OF oDlg
    @ nLin - 1, 288 COMBOBOX oCboCod VAR nCodif ITEMS aCodif SIZE 095, 10 PIXEL OF oDlg

    nLin += 20
    @ nLin, 012 CHECKBOX oChkCsv VAR lCsv ;
                PROMPT "Gerar tambem o CSV analitico (uma linha por componente da arvore)" ;
                SIZE 300, 09 PIXEL OF oDlg

    nLin += 13
    @ nLin, 012 CHECKBOX oChkArv VAR lArvore ;
                PROMPT "Anexar a arvore completa no final do relatorio (deixa o HTML pesado)" ;
                SIZE 300, 09 PIXEL OF oDlg

    nLin += 20
    @ nLin, 010 SAY "Relatorio (servidor):" SIZE 065, 08 PIXEL OF oDlg
    @ nLin - 1, 077 MSGET oGetDir VAR cDirRel SIZE 218, 10 PIXEL OF oDlg

    nLin += 15
    @ nLin, 010 SAY "Copiar p/ (estacao):" SIZE 065, 08 PIXEL OF oDlg
    @ nLin - 1, 077 MSGET oGetEst VAR cDirEst SIZE 218, 10 PIXEL OF oDlg

    nLin += 12
    @ nLin, 077 SAY "Deixe em branco para nao copiar os arquivos para a sua maquina." ;
                SIZE 240, 08 PIXEL OF oDlg

    nLin += 20
    TButton():New(nLin, 195, "Gerar relatorio", oDlg, ;
                  {|| AE01Inicia(cProduto, cRevisao, cFilial, nNivel, ;
                                 lArvore, lCsv, nCodif, cDirRel, cDirEst) }, ;
                  058, 013, , , .F., .T., .F., , .F., , , .F.)

    TButton():New(nLin, 258, "Sair", oDlg, {|| oDlg:End() }, ;
                  058, 013, , , .F., .T., .F., , .F., , , .F.)

    ACTIVATE MSDIALOG oDlg CENTERED

Return Nil


/*/{Protheus.doc} AE01VldPrd
Sugere a revisao atual do cadastro (B1_REVATU) quando o produto e digitado.

Devolve a revisao em vez de recebe-la por referencia: o VALID vira um bloco
de codigo, e passar local por referencia (@) de dentro de bloco nao e
suportado pelo compilador.

A revisao continua editavel - consultar uma revisao diferente da atual e um
uso legitimo da rotina, e o proprio relatorio marca a divergencia como
VERIFICAR.

@param cProduto Codigo digitado
@param cRevisao Revisao que esta na tela hoje
@return cRet    Revisao sugerida (a mesma, quando o produto nao existe)
/*/
Static Function AE01VldPrd(cProduto, cRevisao)

    Local aArea := SB1->(FWGetArea())
    Local cCod  := AllTrim(cProduto)
    Local cRet  := cRevisao

    If Empty(cCod)
        Return cRet
    EndIf

    SB1->(DbSetOrder(1))   // B1_FILIAL + B1_COD

    If SB1->(DbSeek(xFilial("SB1") + PadR(cCod, TamSX3("B1_COD")[1])))
        If !Empty(SB1->B1_REVATU)
            cRet := PadR(AllTrim(SB1->B1_REVATU), 3)
        EndIf
    EndIf

    SB1->(FWRestArea(aArea))

Return cRet


/*/{Protheus.doc} AE01Refr
Atualiza um componente da tela, ignorando quando ele ainda nao existe.

O VALID do campo de produto e montado antes do campo de revisao, entao no
primeiro Refresh o objeto pode nao ter sido instanciado.

@param oObj Componente a atualizar
@return lRet Sempre .T., para poder entrar em expressao de VALID
/*/
Static Function AE01Refr(oObj)

    If ValType(oObj) == "O"
        oObj:Refresh()
    EndIf

Return .T.


/*/{Protheus.doc} AE01Inicia
Critica os parametros, monta o array de configuracao e dispara a auditoria.

@param cProduto Codigo do item principal
@param cRevisao Revisao consultada
@param cFilial  Filial dos filtros
@param nNivel   Profundidade maxima
@param lArvore  .T. = anexa a arvore completa no HTML
@param lCsv     .T. = gera o CSV analitico
@param nCodif   1 = ANSI  2 = UTF-8
@param cDirRel  Diretorio de saida no servidor
@param cDirEst  Diretorio de destino na estacao
/*/
Static Function AE01Inicia(cProduto, cRevisao, cFilial, nNivel, ;
                          lArvore, lCsv, nCodif, cDirRel, cDirEst)

    Local aCfg    := Array(CFG_SIZE)
    Local aRes    := Nil
    Local cArqHtm := ""
    Local cArqCsv := ""
    Local cAviso  := ""
    Local nSegIni := Seconds()
    Local nSegFim := 0

    If Empty(AllTrim(cProduto))
        MsgStop("Informe o codigo do produto que sera auditado.", "Atencao")
        Return Nil
    EndIf

    If Empty(AllTrim(cRevisao))
        MsgStop("Informe a revisao a ser consultada (ex.: " + AUD_REVPAD + ").", "Atencao")
        Return Nil
    EndIf

    If Empty(AllTrim(cFilial))
        MsgStop("Informe a filial usada nos filtros de SB1/SG1/SG2 " + ;
                "(ex.: " + AUD_FILIAL + ").", "Atencao")
        Return Nil
    EndIf

    If nNivel < 1 .Or. nNivel > 99
        MsgStop("O nivel maximo deve ficar entre 1 e 99.", "Atencao")
        Return Nil
    EndIf

    If Empty(AllTrim(cDirRel))
        MsgStop("Informe o diretorio onde o relatorio sera gravado no servidor.", "Atencao")
        Return Nil
    EndIf

    aCfg[CFG_PRODUTO] := Upper(AllTrim(cProduto))
    aCfg[CFG_REVISAO] := Upper(AllTrim(cRevisao))
    aCfg[CFG_FILIAL]  := AllTrim(cFilial)
    aCfg[CFG_NIVEL]   := Int(nNivel)
    aCfg[CFG_ARVORE]  := lArvore
    aCfg[CFG_CSV]     := lCsv
    aCfg[CFG_CODIF]   := nCodif
    aCfg[CFG_DIRREL]  := AllTrim(cDirRel)
    aCfg[CFG_DIREST]  := AllTrim(cDirEst)

    Processa({|| aRes := AE01Proc(aCfg) }, "Auditoria de roteiro / estrutura", ;
             "Explodindo a estrutura...", .F.)

    If ValType(aRes) != "A"
        Return Nil
    EndIf

    If Len(aRes[RES_LINHAS]) == 0
        MsgStop("A consulta nao retornou nenhuma linha para " + aCfg[CFG_PRODUTO] + ;
                " na revisao " + aCfg[CFG_REVISAO] + "." + CRLF + CRLF + ;
                "Confira se o codigo existe no SB1 da filial " + aCfg[CFG_FILIAL] + ".", ;
                "Auditoria")
        Return Nil
    EndIf

    cArqHtm := AE01Rel(aCfg, aRes)

    If aCfg[CFG_CSV]
        cArqCsv := AE01Csv(aCfg, aRes)
    EndIf

    If Empty(cArqHtm)
        MsgStop("Nao foi possivel gravar o relatorio em:" + CRLF + ;
                aCfg[CFG_DIRREL] + CRLF + CRLF + ;
                "Verifique a permissao de escrita da pasta no servidor.", "Atencao")
        Return Nil
    EndIf

    // Leva os arquivos para a maquina do usuario, quando solicitado
    If !Empty(aCfg[CFG_DIREST])
        If !AE01Baixar(cArqHtm, aCfg[CFG_DIREST])
            cAviso := "Nao foi possivel copiar os arquivos para " + aCfg[CFG_DIREST] + "."
        ElseIf !Empty(cArqCsv)
            AE01Baixar(cArqCsv, aCfg[CFG_DIREST])
        EndIf
    EndIf

    nSegFim := Seconds()

    // Seconds() conta a partir da meia-noite: se o processamento virou o dia,
    // a diferenca sai negativa
    If nSegFim < nSegIni
        nSegFim += 86400
    EndIf

    AE01Ver(aCfg, aRes, cArqHtm, cArqCsv, cAviso, nSegFim - nSegIni)

Return Nil


// ===========================================================================
// PROCESSAMENTO
// ===========================================================================

/*/{Protheus.doc} AE01Proc
Nucleo da rotina: executa a explosao no banco, classifica cada componente e
monta os agrupamentos que o relatorio consome.

@param aCfg  Array de configuracao (defines CFG_*)
@return aRes Array de resultado (defines RES_*)
/*/
Static Function AE01Proc(aCfg)

    Local aArea    := FWGetArea()
    Local aRes     := Array(RES_SIZE)
    Local aLinhas  := {}
    Local aPais    := {}    // Indice ordenado {codigo, 1} dos codigos que sao pai
    Local aChapas  := AE01Chapas()
    Local aRegras  := AE01Regras()
    Local aLin     := Nil

    Local cAlias   := GetNextAlias()
    Local cSql     := AE01Sql(aCfg)
    Local cPai     := ""

    Local nI       := 0
    Local nTotal   := 0

    aRes[RES_LINHAS]  := {}
    aRes[RES_ERROS]   := {}
    aRes[RES_ALERTAS] := {}
    aRes[RES_TOTEST]  := {}
    aRes[RES_TOTROT]  := {}
    aRes[RES_CAB]     := Array(CAB_SIZE)
    aRes[RES_QTDEST]  := 0
    aRes[RES_QTDROT]  := 0
    aRes[RES_QTDOUT]  := 0

    ProcRegua(0)
    IncProc("Explodindo a estrutura de " + aCfg[CFG_PRODUTO] + "...")

    DbUseArea(.T., "TOPCONN", TCGenQry(,, cSql), cAlias, .F., .T.)

    If Select(cAlias) == 0
        FWRestArea(aArea)
        MsgStop("Falha ao executar a consulta de estrutura." + CRLF + CRLF + ;
                "Verifique a conexao TOPCONN e se o banco e SQL Server " + ;
                "(a explosao usa CTE recursiva).", "Auditoria")
        Return aRes
    EndIf

    TcSetField(cAlias, "QUANT", "N", 18, 6)
    TcSetField(cAlias, "NIVEL", "N", 4, 0)

    // ---------------------------------------------------------- carga bruta
    While !(cAlias)->(Eof())

        aLin := Array(LIN_SIZE)

        aLin[LIN_NIVEL]     := (cAlias)->NIVEL
        aLin[LIN_CODPAI]    := AllTrim((cAlias)->CODPAI)
        aLin[LIN_CODIGO]    := AllTrim((cAlias)->CODIGO)
        aLin[LIN_DESC]      := AllTrim((cAlias)->DESCRICAO)
        aLin[LIN_TIPO]      := AllTrim((cAlias)->TIPO)
        aLin[LIN_UM]        := AllTrim((cAlias)->UM)
        aLin[LIN_QUANT]     := (cAlias)->QUANT
        aLin[LIN_BLOQ]      := ((cAlias)->BLOQ   == "S")
        aLin[LIN_TEMEST]    := ((cAlias)->TEMEST == "S")
        aLin[LIN_TEMROT]    := ((cAlias)->TEMROT == "S")
        aLin[LIN_REVATU]    := AllTrim((cAlias)->REVATU)
        aLin[LIN_REVCON]    := AllTrim((cAlias)->REVCONS)
        aLin[LIN_NOSB1]     := ((cAlias)->NOSB1  == "S")
        aLin[LIN_CAMINHO]   := AllTrim((cAlias)->CAMINHO)
        aLin[LIN_TEMFILHO]  := .F.
        aLin[LIN_ERREST]    := .F.
        aLin[LIN_ERRROT]    := .F.
        aLin[LIN_ERRQTD]    := .F.
        aLin[LIN_SITUACAO]  := "OK"
        aLin[LIN_MOTIVO]    := ""

        aAdd(aLinhas, aLin)

        // Lista dos codigos que aparecem como pai - e a informacao que no SQL
        // original vinha do EXISTS contra a propria CTE (coluna TemFilho).
        // Fica num indice ordenado: a busca e binaria, nao linha a linha
        cPai := aLin[LIN_CODPAI]
        If !Empty(cPai) .And. AE01Acha(aPais, cPai) == 0
            AE01Ins(aPais, cPai, 1)
        EndIf

        (cAlias)->(DbSkip())
    EndDo

    (cAlias)->(DbCloseArea())

    nTotal := Len(aLinhas)

    // ------------------------------------------------------- classificacao
    ProcRegua(nTotal)

    For nI := 1 To nTotal

        IncProc("Classificando " + cValToChar(nI) + " de " + cValToChar(nTotal) + "...")

        aLin := aLinhas[nI]

        aLin[LIN_TEMFILHO] := (AE01Acha(aPais, aLin[LIN_CODIGO]) > 0)

        // As duas condicoes isoladas alimentam as colunas Estrutura e Roteiro
        // do relatorio; a Situacao da query mostra apenas a primeira delas
        aLin[LIN_ERREST] := AE01ErrEst(aLin, aRegras)
        aLin[LIN_ERRROT] := AE01ErrRot(aLin, aRegras)

        AE01Class(aLin, aChapas, aRegras)

    Next nI

    aRes[RES_LINHAS] := aLinhas

    IncProc("Agrupando os resultados...")

    AE01Agrupa(aCfg, aRes, aRegras)

    FWRestArea(aArea)

Return aRes


/*/{Protheus.doc} AE01Sql
Monta o SELECT de explosao da estrutura.

E a query validada pela engenharia, com tres diferencas, todas comentadas
no cabecalho do fonte:

   - os nomes fisicos vem de RetSqlName(), em vez de fixos em SB1120/SG1120/
     SG2120, para a rotina rodar em qualquer empresa;
   - o DECLARE saiu: os dois parametros entram como literais ja tratados
     contra apostrofo, porque TCGenQry envia um comando unico;
   - a coluna TemFilho e os dois CASE (Situacao/Motivo) sairam do SELECT e
     foram para o ADVPL - TemFilho porque o EXISTS contra a propria CTE
     recursiva faz o SQL Server reexecutar a recursao a cada linha.

Tudo o que define QUAIS linhas entram na arvore (recursao, vigencia por
G1_INI/G1_FIM, faixa de revisao por G1_REVINI/G1_REVFIM, corte de ciclo pelo
Caminho e limite de nivel) continua identico ao original.

@param aCfg  Array de configuracao
@return cSql Texto do comando
/*/
Static Function AE01Sql(aCfg)

    Local cSql := ""
    Local cSB1 := RetSqlName("SB1")
    Local cSG1 := RetSqlName("SG1")
    Local cSG2 := RetSqlName("SG2")

    Local cCod := AE01Lit(aCfg[CFG_PRODUTO])
    Local cRev := AE01Lit(aCfg[CFG_REVISAO])
    Local cFil := AE01Lit(aCfg[CFG_FILIAL])
    Local cNiv := cValToChar(aCfg[CFG_NIVEL])

    cSql += " WITH Estrutura AS ( "
    cSql += "     SELECT "
    cSql += "         0 AS Nivel, "
    cSql += "         CAST(NULL AS VARCHAR(30)) AS CodPai, "
    cSql += "         CAST(" + cCod + " AS VARCHAR(30)) AS Codigo, "
    cSql += "         CAST(1.0 AS FLOAT) AS Quantidade, "
    cSql += "         CAST('|' + " + cCod + " + '|' AS VARCHAR(8000)) AS Caminho, "
    cSql += "         CAST(" + cRev + " AS VARCHAR(3)) AS Revisao "
    cSql += "     UNION ALL "
    cSql += "     SELECT "
    cSql += "         E.Nivel + 1, "
    cSql += "         CAST(RTRIM(G1.G1_COD) AS VARCHAR(30)), "
    cSql += "         CAST(RTRIM(G1.G1_COMP) AS VARCHAR(30)), "
    cSql += "         CAST(G1.G1_QUANT AS FLOAT), "
    cSql += "         CAST(E.Caminho + RTRIM(G1.G1_COMP) + '|' AS VARCHAR(8000)), "
    cSql += "         CAST(ISNULL(NULLIF(RTRIM(( "
    cSql += "             SELECT TOP 1 B1c.B1_REVATU "
    cSql += "             FROM " + cSB1 + " AS B1c "
    cSql += "             WHERE B1c.D_E_L_E_T_ = ' ' "
    cSql += "               AND B1c.B1_FILIAL = " + cFil + " "
    cSql += "               AND CAST(RTRIM(B1c.B1_COD) AS VARCHAR(30)) = "
    cSql += "                   CAST(RTRIM(G1.G1_COMP) AS VARCHAR(30)) "
    cSql += "         )), ''), " + AE01Lit(AUD_REVPAD) + ") AS VARCHAR(3)) "
    cSql += "     FROM Estrutura AS E "
    cSql += "     INNER JOIN " + cSG1 + " AS G1 "
    cSql += "         ON  CAST(RTRIM(G1.G1_COD) AS VARCHAR(30)) = E.Codigo "
    cSql += "         AND G1.G1_FILIAL  = " + cFil + " "
    cSql += "         AND G1.D_E_L_E_T_ = ' ' "
    cSql += "         AND (G1.G1_INI IS NULL OR CONVERT(DATE, G1.G1_INI) <= CONVERT(DATE, GETDATE())) "
    cSql += "         AND (G1.G1_FIM IS NULL OR CONVERT(DATE, G1.G1_FIM) >= CONVERT(DATE, GETDATE())) "
    cSql += "         AND (RTRIM(ISNULL(G1.G1_REVINI, '')) = '' OR RTRIM(G1.G1_REVINI) <= E.Revisao) "
    cSql += "         AND (RTRIM(ISNULL(G1.G1_REVFIM, '')) IN ('', 'ZZZ') OR RTRIM(G1.G1_REVFIM) >= E.Revisao) "
    cSql += "     WHERE E.Nivel < " + cNiv + " "
    cSql += "       AND CHARINDEX('|' + RTRIM(G1.G1_COMP) + '|', E.Caminho) = 0 "
    cSql += " ) "
    cSql += " SELECT "
    cSql += "     E.Nivel                         AS NIVEL, "
    cSql += "     ISNULL(E.CodPai, '')            AS CODPAI, "
    cSql += "     E.Codigo                        AS CODIGO, "
    cSql += "     ISNULL(RTRIM(B1.B1_DESC), '')   AS DESCRICAO, "
    cSql += "     ISNULL(RTRIM(B1.B1_TIPO), '')   AS TIPO, "
    cSql += "     ISNULL(RTRIM(B1.B1_UM), '')     AS UM, "
    cSql += "     E.Quantidade                    AS QUANT, "
    cSql += "     CASE WHEN RTRIM(B1.B1_MSBLQL) = '1' THEN 'S' ELSE 'N' END AS BLOQ, "
    cSql += "     CASE WHEN EXISTS ( "
    cSql += "         SELECT 1 FROM " + cSG1 + " AS G1 "
    cSql += "         WHERE G1.D_E_L_E_T_ = ' ' "
    cSql += "           AND G1.G1_FILIAL = " + cFil + " "
    cSql += "           AND CAST(RTRIM(G1.G1_COD) AS VARCHAR(30)) = E.Codigo "
    cSql += "           AND (G1.G1_INI IS NULL OR CONVERT(DATE, G1.G1_INI) <= CONVERT(DATE, GETDATE())) "
    cSql += "           AND (G1.G1_FIM IS NULL OR CONVERT(DATE, G1.G1_FIM) >= CONVERT(DATE, GETDATE())) "
    cSql += "           AND (RTRIM(ISNULL(G1.G1_REVINI, '')) = '' OR RTRIM(G1.G1_REVINI) <= E.Revisao) "
    cSql += "           AND (RTRIM(ISNULL(G1.G1_REVFIM, '')) IN ('', 'ZZZ') OR RTRIM(G1.G1_REVFIM) >= E.Revisao) "
    cSql += "     ) THEN 'S' ELSE 'N' END         AS TEMEST, "
    cSql += "     CASE WHEN EXISTS ( "
    cSql += "         SELECT 1 FROM " + cSG2 + " AS G2 "
    cSql += "         WHERE G2.D_E_L_E_T_ = ' ' "
    cSql += "           AND G2.G2_FILIAL = " + cFil + " "
    cSql += "           AND CAST(RTRIM(G2.G2_PRODUTO) AS VARCHAR(30)) = E.Codigo "
    cSql += "     ) THEN 'S' ELSE 'N' END         AS TEMROT, "
    cSql += "     ISNULL(NULLIF(RTRIM(B1.B1_REVATU), ''), " + AE01Lit(AUD_REVPAD) + ") AS REVATU, "
    cSql += "     E.Revisao                       AS REVCONS, "
    cSql += "     CASE WHEN B1.B1_COD IS NULL THEN 'N' ELSE 'S' END AS NOSB1, "
    cSql += "     E.Caminho                       AS CAMINHO "
    cSql += " FROM Estrutura AS E "
    cSql += " LEFT JOIN " + cSB1 + " AS B1 "
    cSql += "     ON  CAST(RTRIM(B1.B1_COD) AS VARCHAR(30)) = E.Codigo "
    cSql += "     AND B1.B1_FILIAL  = " + cFil + " "
    cSql += "     AND B1.D_E_L_E_T_ = ' ' "
    cSql += " ORDER BY E.Nivel, E.CodPai, E.Codigo "
    cSql += " OPTION (MAXRECURSION " + cNiv + ") "

Return cSql


/*/{Protheus.doc} AE01Lit
Devolve o texto pronto para entrar no SQL como literal, com o apostrofo
duplicado. Os parametros vem digitados pelo usuario, entao nao podem ser
concatenados crus.

@param cTexto Conteudo original
@return cRet  Literal entre apostrofos
/*/
Static Function AE01Lit(cTexto)
Return "'" + StrTran(AllTrim(cTexto), "'", "''") + "'"


// ===========================================================================
// CLASSIFICACAO - transcricao dos CASE da query original
// ===========================================================================

/*/{Protheus.doc} AE01Folha
Diz se o componente e uma folha valida da arvore.

Regra 1 da especificacao: sao folhas validas MP, SV e os BN/EM que NAO
possuem estrutura vigente. Um BN/EM com estrutura precisa continuar
descendo, como PA e PI.

@param cTipo   B1_TIPO
@param lTemEst .T. quando tem estrutura vigente no SG1
@param aRegras Tabela de AE01Regras()
@return lRet   .T. quando pode parar nesse componente
/*/
Static Function AE01Folha(cTipo, lTemEst, aRegras)

    Local lRet := .F.
    Local nPos := aScan(aRegras, {|x| x[REG_TIPO] == cTipo})

    If nPos > 0
        If aRegras[nPos][REG_FOLHA] == "S"
            lRet := .T.
        ElseIf aRegras[nPos][REG_FOLHA] == "E"
            lRet := !lTemEst
        EndIf
    EndIf

Return lRet


/*/{Protheus.doc} AE01ExRot
Diz se o componente exige roteiro (SG2).

Regra 3: PA/PI sempre exigem, menos o PA Finame; EM/BN so exigem quando tem
estrutura; MP/SV nao exigem. Tipo fora da tabela segue PA/PI - e o que a
query original faz, porque os CASE de MP/SV e BN/EM nao pegam o tipo
desconhecido e a avaliacao cai direto no teste de roteiro.

@param cTipo   B1_TIPO
@param cCod    Codigo do componente
@param lTemEst .T. quando tem estrutura vigente no SG1
@param aRegras Tabela de AE01Regras()
@return lRet   .T. quando o roteiro e obrigatorio
/*/
Static Function AE01ExRot(cTipo, cCod, lTemEst, aRegras)

    Local lRet := .T.
    Local nPos := aScan(aRegras, {|x| x[REG_TIPO] == cTipo})

    If nPos > 0
        lRet := aRegras[nPos][REG_SEMPRE] .Or. ;
                (aRegras[nPos][REG_SEEST] .And. lTemEst)
    EndIf

    // Excecao Finame: PA cujo codigo comeca com FIN nao tem roteiro proprio
    If lRet .And. cTipo == "PA" .And. Left(cCod, Len(AUD_FINAME)) == AUD_FINAME
        lRet := .F.
    EndIf

Return lRet


/*/{Protheus.doc} AE01ErrEst
Erro de estrutura da linha: o componente nao e folha valida e nao desce
para ninguem.

Avaliado por fora da Situacao porque o relatorio precisa das duas colunas
(Estrutura e Roteiro) preenchidas de forma independente - na query, quando
falta roteiro E estrutura, so o roteiro aparece.

@param aLin    Linha da explosao (LIN_*)
@param aRegras Tabela de AE01Regras()
@return lRet   .T. quando ha erro de estrutura
/*/
Static Function AE01ErrEst(aLin, aRegras)

    // Componente que nem existe no SB1 entra na secao de cadastro, nao aqui
    If !aLin[LIN_NOSB1]
        Return .F.
    EndIf

Return !AE01Folha(aLin[LIN_TIPO], aLin[LIN_TEMEST], aRegras) .And. !aLin[LIN_TEMFILHO]


/*/{Protheus.doc} AE01ErrRot
Erro de roteiro da linha: o componente exige SG2 e nao tem.

@param aLin    Linha da explosao (LIN_*)
@param aRegras Tabela de AE01Regras()
@return lRet   .T. quando ha erro de roteiro
/*/
Static Function AE01ErrRot(aLin, aRegras)

    If !aLin[LIN_NOSB1]
        Return .F.
    EndIf

Return AE01ExRot(aLin[LIN_TIPO], aLin[LIN_CODIGO], aLin[LIN_TEMEST], aRegras) .And. ;
       !aLin[LIN_TEMROT]


/*/{Protheus.doc} AE01Class
Preenche Situacao e Motivo da linha.

Transcricao dos dois CASE da query original, NA MESMA ORDEM. A ordem e a
regra: quando o mesmo componente tem mais de um problema, prevalece o
primeiro Case que fechar. As clausulas 5 e 6 (folha valida) devolvem OK e
por isso um MP bloqueado nunca chega na clausula 9 - comportamento do
original, mantido de proposito.

   1  componente inexistente no SB1 .................. ERRO
   2  chapa com UM diferente de KG .................... ERRO
   3  chapa em KG acima do peso de uma chapa 3000x1200  ERRO
   4  componente em MM acima do limite ................ ERRO
   5  MP / SV ......................................... OK
   6  BN / EM sem estrutura vigente ................... OK
   7  sem roteiro no SG2 (menos PA Finame) ............ ERRO
   8  nao desce ate uma folha valida .................. ERRO
   9  item bloqueado (B1_MSBLQL = 1) .................. VERIFICAR
   10 revisao consultada <> B1_REVATU (so no nivel 0) . VERIFICAR
   11 demais .......................................... OK

@param aLin    Linha da explosao, alterada por referencia
@param aChapas Tabela de AE01Chapas()
@param aRegras Tabela de AE01Regras()
/*/
Static Function AE01Class(aLin, aChapas, aRegras)

    Local cCod  := aLin[LIN_CODIGO]
    Local cTipo := aLin[LIN_TIPO]
    Local cUM   := aLin[LIN_UM]
    Local nQtd  := aLin[LIN_QUANT]
    Local nPos  := aScan(aChapas, {|x| x[1] == cCod})

    Local cSit  := "OK"
    Local cMot  := ""
    Local lQtd  := .F.

    Do Case
        // 1 - componente que a estrutura aponta mas nao existe no cadastro
        Case !aLin[LIN_NOSB1]
            cSit := "ERRO"
            cMot := "Componente nao encontrado no SB1"
            lQtd := .T.

        // 2 - chapa precisa estar em KG
        Case nPos > 0 .And. !(cUM == "KG")
            cSit := "ERRO"
            cMot := "Chapa com unidade diferente de KG"
            lQtd := .T.

        // 3 - teto de chapa, testado linha a linha
        Case nPos > 0 .And. cUM == "KG" .And. nQtd > aChapas[nPos][2]
            cSit := "ERRO"
            cMot := "Quantidade da chapa maior que o peso de uma chapa 3000x1200 " + ;
                    "(teto " + AE01Num(aChapas[nPos][2]) + " KG)"
            lQtd := .T.

        // 4 - medida linear fora do comprimento de barra
        Case cUM == "MM" .And. nQtd > AUD_LIMMM
            cSit := "ERRO"
            cMot := "Quantidade em MM maior que " + cValToChar(AUD_LIMMM)
            lQtd := .T.

        // 5 e 6 - folha valida encerra a analise do ramo
        Case AE01Folha(cTipo, aLin[LIN_TEMEST], aRegras)
            cSit := "OK"

        // 7 - roteiro obrigatorio ausente
        Case !aLin[LIN_TEMROT] .And. ;
             !(cTipo == "PA" .And. Left(cCod, Len(AUD_FINAME)) == AUD_FINAME)
            cSit := "ERRO"
            cMot := "Sem roteiro (SG2)"

        // 8 - nao desce ate uma folha valida
        Case !aLin[LIN_TEMFILHO]
            cSit := "ERRO"
            cMot := "Sem estrutura / nao desce ate folha valida"

        // 9 - item bloqueado
        Case aLin[LIN_BLOQ]
            cSit := "VERIFICAR"
            cMot := "Item bloqueado"

        // 10 - so o principal carrega a revisao informada pelo usuario
        Case aLin[LIN_NIVEL] == 0 .And. !(aLin[LIN_REVATU] == aLin[LIN_REVCON])
            cSit := "VERIFICAR"
            cMot := "Revisao consultada diferente da revisao atual (B1_REVATU " + ;
                    aLin[LIN_REVATU] + ")"
    EndCase

    aLin[LIN_SITUACAO] := cSit
    aLin[LIN_MOTIVO]   := cMot
    aLin[LIN_ERRQTD]   := lQtd

Return Nil


// ===========================================================================
// AGRUPAMENTO
// ===========================================================================

// --- Posicoes do array de codigos unicos (uso interno de AE01Agrupa) --------
#DEFINE UNI_CODIGO    1
#DEFINE UNI_DESC      2
#DEFINE UNI_TIPO      3
#DEFINE UNI_OCORR     4
#DEFINE UNI_TEMROT    5
#DEFINE UNI_EXIGROT   6
#DEFINE UNI_ERREST    7
#DEFINE UNI_ERRROT    8
#DEFINE UNI_ERRQTD    9
#DEFINE UNI_SIT      10
#DEFINE UNI_MOTIVOS  11    // Array de motivos distintos
#DEFINE UNI_PAIS     12    // Array de {cPai, nNivel}
#DEFINE UNI_FOLHA    13    // .T. = e folha valida (a regra de estrutura nao se aplica)
#DEFINE UNI_NOSB1    14    // .T. = o codigo existe no SB1

/*/{Protheus.doc} AE01Agrupa
Monta, a partir das linhas ja classificadas, tudo o que o relatorio consome:
cabecalho, lista de codigos unicos com erro, lista de alertas e os dois
quadros por tipo.

Os dois quadros contam de formas diferentes, igual ao documento modelo:

   ANALISE DE ESTRUTURA . por OCORRENCIA na arvore (o mesmo codigo em dois
                          pais conta duas vezes);
   ANALISE DE ROTEIRO ... por CODIGO UNICO (roteiro e cadastro do item, nao
                          da posicao dele na arvore).

@param aCfg    Array de configuracao
@param aRes    Array de resultado, alterado por referencia
@param aRegras Tabela de AE01Regras()
/*/
Static Function AE01Agrupa(aCfg, aRes, aRegras)

    Local aLinhas := aRes[RES_LINHAS]
    Local aUni    := {}
    Local aOrd    := {}    // Indice ordenado {codigo, posicao em aUni}
    Local aErr    := Nil
    Local aLin    := Nil

    Local cTipo   := ""
    Local cCod    := ""

    Local nI      := 0
    Local nJ      := 0
    Local nPos    := 0

    // ---------------------------------------------------- codigos unicos
    // O indice aOrd evita varrer aUni inteiro a cada linha: numa arvore de
    // milhares de itens a busca linear aqui dominaria o tempo da rotina
    For nI := 1 To Len(aLinhas)

        aLin := aLinhas[nI]
        cCod := aLin[LIN_CODIGO]
        nPos := AE01Acha(aOrd, cCod)

        If nPos == 0
            aAdd(aUni, {cCod                , ;
                        aLin[LIN_DESC]      , ;
                        aLin[LIN_TIPO]      , ;
                        0                   , ;
                        aLin[LIN_TEMROT]    , ;
                        AE01ExRot(aLin[LIN_TIPO], cCod, aLin[LIN_TEMEST], aRegras), ;
                        aLin[LIN_ERREST]    , ;
                        aLin[LIN_ERRROT]    , ;
                        .F.                 , ;
                        "OK"                , ;
                        {}                  , ;
                        {}                  , ;
                        AE01Folha(aLin[LIN_TIPO], aLin[LIN_TEMEST], aRegras), ;
                        aLin[LIN_NOSB1]     })

            nPos := Len(aUni)
            AE01Ins(aOrd, cCod, nPos)
        EndIf

        aUni[nPos][UNI_OCORR]++

        If aLin[LIN_ERRQTD]
            aUni[nPos][UNI_ERRQTD] := .T.
        EndIf

        // Pior situacao encontrada entre as ocorrencias do codigo
        If aLin[LIN_SITUACAO] == "ERRO"
            aUni[nPos][UNI_SIT] := "ERRO"
        ElseIf aLin[LIN_SITUACAO] == "VERIFICAR" .And. aUni[nPos][UNI_SIT] == "OK"
            aUni[nPos][UNI_SIT] := "VERIFICAR"
        EndIf

        If !Empty(aLin[LIN_MOTIVO]) .And. ;
           aScan(aUni[nPos][UNI_MOTIVOS], {|x| x == aLin[LIN_MOTIVO]}) == 0
            aAdd(aUni[nPos][UNI_MOTIVOS], aLin[LIN_MOTIVO])
        EndIf

    Next nI

    // ------------------------------------------------------- cabecalho
    nPos := aScan(aLinhas, {|x| x[LIN_NIVEL] == 0})

    If nPos > 0
        aRes[RES_CAB][CAB_CODIGO]  := aLinhas[nPos][LIN_CODIGO]
        aRes[RES_CAB][CAB_DESC]    := aLinhas[nPos][LIN_DESC]
        aRes[RES_CAB][CAB_TIPO]    := aLinhas[nPos][LIN_TIPO]
        aRes[RES_CAB][CAB_REVATU]  := aLinhas[nPos][LIN_REVATU]

        // O PA Finame ganha o rotulo no cabecalho porque a dispensa de
        // roteiro do principal so faz sentido lida junto com o tipo
        If aRes[RES_CAB][CAB_TIPO] == "PA" .And. ;
           Left(aRes[RES_CAB][CAB_CODIGO], Len(AUD_FINAME)) == AUD_FINAME
            aRes[RES_CAB][CAB_TIPO] += " Finame"
        EndIf
    Else
        aRes[RES_CAB][CAB_CODIGO] := aCfg[CFG_PRODUTO]
        aRes[RES_CAB][CAB_DESC]   := ""
        aRes[RES_CAB][CAB_TIPO]   := ""
        aRes[RES_CAB][CAB_REVATU] := ""
    EndIf

    aRes[RES_CAB][CAB_REVISAO] := aCfg[CFG_REVISAO]
    aRes[RES_CAB][CAB_FILIAL]  := aCfg[CFG_FILIAL]

    // ------------------------------------------------------ codigos pai
    // Passada separada, e so para quem tem ocorrencia: um parafuso usado em
    // 800 pais nao interessa ao relatorio e a deduplicacao dele custaria caro
    For nI := 1 To Len(aLinhas)

        aLin := aLinhas[nI]

        If Empty(aLin[LIN_CODPAI])
            Loop
        EndIf

        nPos := AE01Acha(aOrd, aLin[LIN_CODIGO])

        If nPos == 0 .Or. aUni[nPos][UNI_SIT] == "OK"
            Loop
        EndIf

        If aScan(aUni[nPos][UNI_PAIS], {|x| x[1] == aLin[LIN_CODPAI]}) == 0
            aAdd(aUni[nPos][UNI_PAIS], {aLin[LIN_CODPAI], aLin[LIN_NIVEL]})
        EndIf

    Next nI

    // --------------------------------------- erros, alertas e contadores
    For nI := 1 To Len(aUni)

        If aUni[nI][UNI_ERREST]
            aRes[RES_QTDEST]++
        EndIf

        If aUni[nI][UNI_ERRROT]
            aRes[RES_QTDROT]++
        EndIf

        If aUni[nI][UNI_ERRQTD]
            aRes[RES_QTDOUT]++
        EndIf

        If aUni[nI][UNI_SIT] == "OK"
            Loop
        EndIf

        aErr := Array(ERR_SIZE)

        aErr[ERR_CODIGO] := aUni[nI][UNI_CODIGO]
        aErr[ERR_DESC]   := aUni[nI][UNI_DESC]
        aErr[ERR_TIPO]   := aUni[nI][UNI_TIPO]
        aErr[ERR_OCORR]  := aUni[nI][UNI_OCORR]
        aErr[ERR_PAIS]   := aUni[nI][UNI_PAIS]
        aErr[ERR_MOTIVO] := ""

        For nJ := 1 To Len(aUni[nI][UNI_MOTIVOS])
            aErr[ERR_MOTIVO] += IIf(nJ > 1, " | ", "") + aUni[nI][UNI_MOTIVOS][nJ]
        Next nJ

        // "-" quando a regra nem se aplica: MP sem roteiro nao e OK nem ERRO,
        // e simplesmente nao avaliado. Idem estrutura numa folha valida, ou
        // qualquer das duas num componente que nem existe no SB1
        If !aUni[nI][UNI_NOSB1]
            aErr[ERR_EST] := "-"
            aErr[ERR_ROT] := "-"
        Else
            aErr[ERR_EST] := IIf(aUni[nI][UNI_FOLHA], "-", ;
                                 IIf(aUni[nI][UNI_ERREST], "ERRO", "OK"))
            aErr[ERR_ROT] := IIf(aUni[nI][UNI_EXIGROT], ;
                                 IIf(aUni[nI][UNI_ERRROT], "ERRO", "OK"), "-")
        EndIf

        If aUni[nI][UNI_SIT] == "ERRO"
            aAdd(aRes[RES_ERROS], aErr)
        Else
            aAdd(aRes[RES_ALERTAS], aErr)
        EndIf

    Next nI

    // ------------------------------------- quadro por tipo: ESTRUTURA
    // Conta OCORRENCIAS. A ordem das linhas vem de AE01Regras(); tipos que
    // aparecerem na arvore e nao estiverem la entram no final
    For nI := 1 To Len(aRegras)
        aAdd(aRes[RES_TOTEST], {aRegras[nI][REG_TIPO], 0, 0, 0})
    Next nI

    For nI := 1 To Len(aLinhas)

        cTipo := aLinhas[nI][LIN_TIPO]

        If Empty(cTipo)
            cTipo := AUD_SEMCAD
        EndIf

        nPos := aScan(aRes[RES_TOTEST], {|x| x[TOT_TIPO] == cTipo})

        If nPos == 0
            aAdd(aRes[RES_TOTEST], {cTipo, 0, 0, 0})
            nPos := Len(aRes[RES_TOTEST])
        EndIf

        aRes[RES_TOTEST][nPos][TOT_TOTAL]++

        If aLinhas[nI][LIN_ERREST]
            aRes[RES_TOTEST][nPos][TOT_SEMEST]++
        Else
            aRes[RES_TOTEST][nPos][TOT_OK]++
        EndIf

    Next nI

    // --------------------------------------- quadro por tipo: ROTEIRO
    // Conta CODIGOS UNICOS
    For nI := 1 To Len(aRegras)
        aAdd(aRes[RES_TOTROT], {aRegras[nI][REG_TIPO], 0, 0, 0, 0, ;
                                aRegras[nI][REG_EXIGE]})
    Next nI

    For nI := 1 To Len(aUni)

        cTipo := aUni[nI][UNI_TIPO]

        If Empty(cTipo)
            cTipo := AUD_SEMCAD
        EndIf

        nPos := aScan(aRes[RES_TOTROT], {|x| x[ROT_TIPO] == cTipo})

        If nPos == 0
            // Tipo fora de AE01Regras() segue PA/PI e exige roteiro; o item
            // que nem esta no SB1 nao chega a ser avaliado
            aAdd(aRes[RES_TOTROT], {cTipo, 0, 0, 0, 0, ;
                                    IIf(cTipo == AUD_SEMCAD, "&mdash;", "Sim")})
            nPos := Len(aRes[RES_TOTROT])
        EndIf

        aRes[RES_TOTROT][nPos][ROT_UNICOS]++

        If aUni[nI][UNI_TEMROT]
            aRes[RES_TOTROT][nPos][ROT_COM]++
        Else
            aRes[RES_TOTROT][nPos][ROT_SEM]++
        EndIf

        If aUni[nI][UNI_ERRROT]
            aRes[RES_TOTROT][nPos][ROT_ERRO]++
        EndIf

    Next nI

    // Tira do relatorio os tipos previstos em AE01Regras() que nao apareceram
    For nI := Len(aRes[RES_TOTEST]) To 1 Step -1
        If aRes[RES_TOTEST][nI][TOT_TOTAL] == 0
            aDel(aRes[RES_TOTEST], nI)
            aRes[RES_TOTEST] := aSize(aRes[RES_TOTEST], Len(aRes[RES_TOTEST]) - 1)
        EndIf
    Next nI

    For nI := Len(aRes[RES_TOTROT]) To 1 Step -1
        If aRes[RES_TOTROT][nI][ROT_UNICOS] == 0
            aDel(aRes[RES_TOTROT], nI)
            aRes[RES_TOTROT] := aSize(aRes[RES_TOTROT], Len(aRes[RES_TOTROT]) - 1)
        EndIf
    Next nI

Return Nil


/*/{Protheus.doc} AE01Acha
Busca binaria num indice ordenado de {chave, valor}.

Existe para tirar a busca linear de dentro dos lacos que percorrem a arvore
inteira - com alguns milhares de linhas, o aScan com bloco de codigo em cada
uma delas passa a dominar o tempo da rotina.

@param aOrd   Indice ordenado por [1], montado por AE01Ins()
@param cChave Chave procurada
@return nRet  Valor associado, ou 0 quando a chave nao esta no indice
/*/
Static Function AE01Acha(aOrd, cChave)

    Local nIni := 1
    Local nFim := Len(aOrd)
    Local nMei := 0

    Do While nIni <= nFim

        nMei := Int((nIni + nFim) / 2)

        If aOrd[nMei][1] == cChave
            Return aOrd[nMei][2]
        ElseIf aOrd[nMei][1] < cChave
            nIni := nMei + 1
        Else
            nFim := nMei - 1
        EndIf

    EndDo

Return 0


/*/{Protheus.doc} AE01Ins
Insere {chave, valor} no indice mantendo a ordem por chave.

aIns abre espaco na posicao e descarta o ultimo elemento, entao o array
precisa crescer antes - por isso o aAdd de um Nil.

@param aOrd   Indice ordenado, alterado por referencia
@param cChave Chave a inserir (nao pode ja existir)
@param nValor Valor associado
/*/
Static Function AE01Ins(aOrd, cChave, nValor)

    Local nIni := 1
    Local nFim := Len(aOrd)
    Local nMei := 0
    Local nPos := Len(aOrd) + 1

    Do While nIni <= nFim

        nMei := Int((nIni + nFim) / 2)

        If aOrd[nMei][1] < cChave
            nIni := nMei + 1
        Else
            nPos := nMei
            nFim := nMei - 1
        EndIf

    EndDo

    aAdd(aOrd, Nil)
    aIns(aOrd, nPos)

    aOrd[nPos] := {cChave, nValor}

Return Nil


// ===========================================================================
// RELATORIO HTML
// ===========================================================================

/*/{Protheus.doc} AE01Rel
Gera o relatorio no mesmo padrao visual do documento de auditoria da
engenharia: faixa de identificacao, quadro de erros com os cartoes de
contagem, os dois quadros de analise por tipo e o quadro de criterios.

O HTML e montado em array e gravado de uma vez. Concatenar direto em string
faria copia a cada "+=" e, em arvores grandes, o custo pesa.

Todo texto fixo do relatorio usa entidade HTML nos acentos - assim o arquivo
sai correto tanto em ANSI quanto em UTF-8, e so o conteudo vindo do SB1
depende da opcao de codificacao.

@param aCfg  Array de configuracao
@param aRes  Array de resultado
@return cArq Caminho do HTML no servidor ("" em caso de falha)
/*/
Static Function AE01Rel(aCfg, aRes)

    Local aHtm := {}
    Local cDir := aCfg[CFG_DIRREL]
    Local cArq := ""
    Local cAux := ""
    Local nHdl := 0
    Local nI   := 0
    Local nSec := 0

    If Right(cDir, 1) != "\"
        cDir += "\"
    EndIf

    AE01MkDir(cDir)

    cArq := cDir + "AUDEST_" + AE01Nome(aRes[RES_CAB][CAB_CODIGO]) + "_" + ;
            DToS(Date()) + "_" + StrTran(Time(), ":", "") + ".html"

    AE01Cab(aHtm, aCfg, aRes)

    nSec++
    AE01Erros(aHtm, aRes, nSec)

    If Len(aRes[RES_ALERTAS]) > 0
        nSec++
        AE01Alerta(aHtm, aRes, nSec)
    EndIf

    nSec++
    AE01Analis(aHtm, aRes, nSec)

    nSec++
    AE01Regr(aHtm, nSec, aCfg[CFG_FILIAL])

    If aCfg[CFG_ARVORE]
        nSec++
        AE01Arvore(aHtm, aRes, nSec)
    EndIf

    AE01Rodape(aHtm, aCfg, aRes)

    nHdl := FCreate(cArq)

    If nHdl == -1
        ConOut("[zAudEst] Nao foi possivel criar o relatorio: " + cArq + ;
               " (FError " + cValToChar(FError()) + ")")
        Return ""
    EndIf

    For nI := 1 To Len(aHtm)
        cAux := aHtm[nI] + CRLF
        If aCfg[CFG_CODIF] == 2
            cAux := EncodeUTF8(cAux)
        EndIf
        FWrite(nHdl, cAux)
    Next nI

    FClose(nHdl)

Return cArq


/*/{Protheus.doc} AE01Cab
Abre o HTML: folha de estilo, faixa de identificacao e a tira com tipo,
revisao, filial e data.

Toda a aparencia do relatorio esta concentrada no <style> daqui - as demais
funcoes so montam tabelas e aplicam as classes.

@param aHtm Array do HTML, alterado por referencia
@param aCfg Array de configuracao
@param aRes Array de resultado
/*/
Static Function AE01Cab(aHtm, aCfg, aRes)

    Local aCab  := aRes[RES_CAB]
    Local cTipo := IIf(Empty(aCab[CAB_TIPO]), "-", aCab[CAB_TIPO])

    aAdd(aHtm, '<!DOCTYPE html>')
    aAdd(aHtm, '<html lang="pt-br">')
    aAdd(aHtm, '<head>')
    aAdd(aHtm, '<meta charset="' + IIf(aCfg[CFG_CODIF] == 2, "utf-8", "windows-1252") + '">')
    aAdd(aHtm, '<title>Auditoria Roteiro/Estrutura - ' + AE01Esc(aCab[CAB_CODIGO]) + '</title>')
    aAdd(aHtm, '<style>')
    aAdd(aHtm, '  * { box-sizing: border-box; }')
    aAdd(aHtm, '  body { margin:0; padding:0; background:#EDEFF3; color:' + COR_TINTA + ';')
    aAdd(aHtm, '         font-family:"Segoe UI",Roboto,Arial,Helvetica,sans-serif; font-size:12px; }')
    aAdd(aHtm, '  .pg { max-width:1060px; margin:20px auto; background:#FFF; padding:28px 32px 30px; }')
    aAdd(aHtm, '  .tag { font-size:10px; font-weight:700; letter-spacing:.10em; color:' + COR_SUAVE + '; }')
    aAdd(aHtm, '  .tag i { color:#3355FF; font-style:normal; }')
    aAdd(aHtm, '  h1 { font-size:26px; margin:7px 0 3px; letter-spacing:.01em; }')
    aAdd(aHtm, '  .sub { color:' + COR_SUAVE + '; font-size:12px; margin:0 0 16px; }')
    aAdd(aHtm, '  table { border-collapse:collapse; width:100%; }')
    aAdd(aHtm, '  .meta td { background:' + COR_FDCINZA + '; padding:9px 12px; width:25%;')
    aAdd(aHtm, '             border-right:3px solid #FFF; }')
    aAdd(aHtm, '  .meta td:last-child { border-right:0; }')
    aAdd(aHtm, '  .meta b { display:block; font-size:9px; letter-spacing:.12em; color:' + COR_SUAVE + '; }')
    aAdd(aHtm, '  .meta span { display:block; font-size:13px; font-weight:700; margin-top:3px; }')
    aAdd(aHtm, '  .sec { background:' + COR_TINTA + '; color:#FFF; font-size:13px; font-weight:700;')
    aAdd(aHtm, '         letter-spacing:.06em; padding:8px 12px; margin:24px 0 12px; }')
    aAdd(aHtm, '  .sec i { color:' + COR_AZULCLA + '; font-style:normal; padding-right:16px; }')
    aAdd(aHtm, '  .kpi td { width:33.33%; padding:14px 10px; text-align:center;')
    aAdd(aHtm, '            border:3px solid #FFF; }')
    aAdd(aHtm, '  .kpi .n { display:block; font-size:30px; font-weight:700; line-height:1.1; }')
    aAdd(aHtm, '  .kpi .t { display:block; font-size:11px; font-weight:700; letter-spacing:.06em;')
    aAdd(aHtm, '            margin-top:4px; }')
    aAdd(aHtm, '  .kpi .s { display:block; font-size:10px; color:' + COR_SUAVE + '; margin-top:2px; }')
    aAdd(aHtm, '  .g th { background:' + COR_TINTA + '; color:#FFF; font-size:11px; font-weight:700;')
    aAdd(aHtm, '          letter-spacing:.04em; text-align:left; padding:7px 9px; }')
    aAdd(aHtm, '  .g td { padding:7px 9px; border-bottom:1px solid ' + COR_BORDA + '; vertical-align:top; }')
    aAdd(aHtm, '  .g tr.alt { background:' + COR_FDCINZA + '; }')
    aAdd(aHtm, '  .g .cod { font-weight:700; font-size:12px; white-space:nowrap; }')
    aAdd(aHtm, '  .g .dim { color:' + COR_SUAVE + '; font-size:11px; }')
    aAdd(aHtm, '  .c { text-align:center; }')
    aAdd(aHtm, '  .r { text-align:right; }')
    aAdd(aHtm, '  .ok   { background:' + COR_FDVERDE + '; color:' + COR_VERDE + '; font-weight:700; text-align:center; }')
    aAdd(aHtm, '  .err  { background:' + COR_FDVERM  + '; color:' + COR_VERM  + '; font-weight:700; text-align:center; }')
    aAdd(aHtm, '  .ver  { background:' + COR_FDAMBAR + '; color:' + COR_AMBAR + '; font-weight:700; text-align:center; }')
    aAdd(aHtm, '  .na   { color:' + COR_SUAVE + '; text-align:center; }')
    aAdd(aHtm, '  .q th.cap { font-size:13px; letter-spacing:.06em; text-align:center; padding:8px; }')
    aAdd(aHtm, '  .q th { font-size:11px; text-align:center; padding:6px 8px; color:#FFF; }')
    aAdd(aHtm, '  .q td { padding:6px 8px; border-bottom:1px solid ' + COR_BORDA + '; text-align:center; }')
    aAdd(aHtm, '  .q td.tp { text-align:left; font-weight:700; }')
    aAdd(aHtm, '  .q tr.alt { background:' + COR_FDCINZA + '; }')
    aAdd(aHtm, '  .q tr.tot td { background:' + COR_FDAZUL + '; color:' + COR_AZUL + '; font-weight:700;')
    aAdd(aHtm, '                 border-bottom:0; }')
    aAdd(aHtm, '  .qe th { background:' + COR_AZUL + '; }')
    aAdd(aHtm, '  .qr th { background:' + COR_VERDESC + '; }')
    aAdd(aHtm, '  .obs { font-size:11px; padding:10px 12px; margin:0 0 22px; }')
    aAdd(aHtm, '  .obs b { font-weight:700; }')
    aAdd(aHtm, '  .obs span { color:' + COR_SUAVE + '; }')
    aAdd(aHtm, '  .obse { background:' + COR_FDAZUL2 + '; }  .obse b { color:' + COR_AZUL + '; }')
    aAdd(aHtm, '  .obsr { background:' + COR_FDVERD2 + '; }  .obsr b { color:' + COR_VERDESC + '; }')
    aAdd(aHtm, '  .acao { padding:11px 14px; margin:14px 0 0; border-left:4px solid ' + COR_VERM + ';')
    aAdd(aHtm, '          background:' + COR_FDVERM + '; font-size:12px; }')
    aAdd(aHtm, '  .acao b { color:' + COR_VERM + '; letter-spacing:.06em; padding-right:8px; }')
    aAdd(aHtm, '  .acaok { border-left-color:' + COR_VERDE + '; background:' + COR_FDVERDE + '; }')
    aAdd(aHtm, '  .acaok b { color:' + COR_VERDE + '; }')
    aAdd(aHtm, '  .cri td { font-size:11px; padding:8px 10px; width:50%;')
    aAdd(aHtm, '            border-bottom:1px solid ' + COR_BORDA + '; }')
    aAdd(aHtm, '  .cri tr.alt { background:' + COR_FDCINZA + '; }')
    aAdd(aHtm, '  .cri b { color:' + COR_AZUL + '; }')
    aAdd(aHtm, '  .pe { font-size:10px; color:' + COR_SUAVE + '; margin-top:26px;')
    aAdd(aHtm, '        border-top:1px solid ' + COR_BORDA + '; padding-top:10px; }')
    aAdd(aHtm, '  @media print {')
    aAdd(aHtm, '    body { background:#FFF; }')
    aAdd(aHtm, '    .pg { margin:0; max-width:none; padding:0; }')
    aAdd(aHtm, '    tr, .obs, .acao { page-break-inside:avoid; }')
    aAdd(aHtm, '    .sec { page-break-after:avoid; }')
    aAdd(aHtm, '  }')
    aAdd(aHtm, '  @page { size:A4 landscape; margin:12mm; }')
    aAdd(aHtm, '</style>')
    aAdd(aHtm, '</head>')
    aAdd(aHtm, '<body>')
    aAdd(aHtm, '<div class="pg">')

    aAdd(aHtm, '<div class="tag"><i>&#9642;</i> AUDITORIA &nbsp; ROTEIRO/ESTRUTURA</div>')
    aAdd(aHtm, '<h1>' + AE01Esc(aCab[CAB_CODIGO]) + '</h1>')
    aAdd(aHtm, '<p class="sub">' + AE01Esc(aCab[CAB_DESC]) + '</p>')

    aAdd(aHtm, '<table class="meta"><tr>')
    aAdd(aHtm, '<td><b>TIPO</b><span>' + AE01Esc(cTipo) + '</span></td>')
    aAdd(aHtm, '<td><b>REVIS&Atilde;O</b><span>' + AE01Esc(aCab[CAB_REVISAO]) + '</span></td>')
    aAdd(aHtm, '<td><b>FILIAL</b><span>' + AE01Esc(aCab[CAB_FILIAL]) + '</span></td>')
    aAdd(aHtm, '<td><b>DATA</b><span>' + DToC(Date()) + '</span></td>')
    aAdd(aHtm, '</tr></table>')

Return Nil


/*/{Protheus.doc} AE01Erros
Secao 1 - ERROS ENCONTRADOS: os cartoes de contagem, a tabela com um
codigo unico por linha e o quadro de acao necessaria.

Os cartoes contam CODIGOS UNICOS por natureza de erro, e o total e a soma
das tres naturezas - o mesmo codigo pode entrar em mais de uma, quando lhe
falta estrutura e roteiro ao mesmo tempo.

@param aHtm Array do HTML, alterado por referencia
@param aRes Array de resultado
@param nSec Numero da secao
/*/
Static Function AE01Erros(aHtm, aRes, nSec)

    Local aErr   := aRes[RES_ERROS]
    Local nTotal := aRes[RES_QTDEST] + aRes[RES_QTDROT] + aRes[RES_QTDOUT]
    Local nI     := 0

    AE01Sec(aHtm, nSec, "ERROS ENCONTRADOS")

    // ------------------------------------------------------------- cartoes
    aAdd(aHtm, '<table class="kpi"><tr>')
    AE01Card(aHtm, aRes[RES_QTDEST], "ERROS DE ESTRUTURA", "c&oacute;digos &uacute;nicos")
    AE01Card(aHtm, aRes[RES_QTDROT], "ERROS DE ROTEIRO"  , "c&oacute;digos &uacute;nicos")
    AE01Card(aHtm, aRes[RES_QTDOUT], "QUANTIDADE / CADASTRO", "c&oacute;digos &uacute;nicos")
    aAdd(aHtm, '</tr><tr>')
    aAdd(aHtm, '<td colspan="3" style="background:' + COR_FDAZUL + ';">')
    aAdd(aHtm, '<span class="n" style="color:' + IIf(nTotal > 0, COR_VERM, COR_VERDE) + ';">' + ;
               AE01Zero(nTotal) + '</span>')
    aAdd(aHtm, '<span class="t">ERROS NO TOTAL</span>')
    aAdd(aHtm, '<span class="s">resultado</span></td>')
    aAdd(aHtm, '</tr></table>')

    // -------------------------------------------------------------- tabela
    If Len(aErr) == 0
        aAdd(aHtm, '<div class="acao acaok"><b>NENHUM ERRO</b>')
        aAdd(aHtm, 'A estrutura desce at&eacute; folha v&aacute;lida em todos os ramos e ' + ;
                   'todos os itens que exigem roteiro possuem SG2.</div>')
        Return Nil
    EndIf

    aAdd(aHtm, '<table class="g">')
    aAdd(aHtm, '<colgroup><col style="width:15%"><col style="width:20%">')
    aAdd(aHtm, '<col style="width:6%"><col style="width:9%"><col style="width:9%">')
    aAdd(aHtm, '<col style="width:21%"><col style="width:20%"></colgroup>')
    aAdd(aHtm, '<tr>')
    aAdd(aHtm, '<th>C&oacute;digo</th><th>Descri&ccedil;&atilde;o</th>')
    aAdd(aHtm, '<th class="c">Ocorr.</th><th class="c">Estrutura</th><th class="c">Roteiro</th>')
    aAdd(aHtm, '<th>Motivo</th><th>C&oacute;digo pai</th>')
    aAdd(aHtm, '</tr>')

    For nI := 1 To Len(aErr)
        aAdd(aHtm, '<tr' + IIf(nI % 2 == 0, ' class="alt"', '') + '>')
        aAdd(aHtm, '<td class="cod">' + AE01Esc(aErr[nI][ERR_CODIGO]) + '</td>')
        aAdd(aHtm, '<td class="dim">' + AE01Esc(aErr[nI][ERR_DESC]) + '</td>')
        aAdd(aHtm, '<td class="c">' + cValToChar(aErr[nI][ERR_OCORR]) + '</td>')
        aAdd(aHtm, AE01Selo(aErr[nI][ERR_EST]))
        aAdd(aHtm, AE01Selo(aErr[nI][ERR_ROT]))
        aAdd(aHtm, '<td class="dim">' + AE01Esc(aErr[nI][ERR_MOTIVO]) + '</td>')
        aAdd(aHtm, '<td class="dim">' + AE01Pais(aErr[nI][ERR_PAIS]) + '</td>')
        aAdd(aHtm, '</tr>')
    Next nI

    aAdd(aHtm, '</table>')

    AE01Acao(aHtm, aRes)

Return Nil


/*/{Protheus.doc} AE01Acao
Quadro "ACAO NECESSARIA", montado a partir do que realmente foi encontrado.

@param aHtm Array do HTML, alterado por referencia
@param aRes Array de resultado
/*/
Static Function AE01Acao(aHtm, aRes)

    Local cTxt := ""

    If aRes[RES_QTDEST] > 0
        cTxt += "Criar estrutura vigente para " + AE01Cods(aRes[RES_QTDEST]) + ;
                " marcado(s) com ERRO na coluna Estrutura. "
    EndIf

    If aRes[RES_QTDROT] > 0
        cTxt += "Cadastrar roteiro (SG2) para " + AE01Cods(aRes[RES_QTDROT]) + ;
                " marcado(s) com ERRO na coluna Roteiro - corrigir a estrutura " + ;
                "n&atilde;o resolve o roteiro. "
    EndIf

    If aRes[RES_QTDOUT] > 0
        cTxt += "Revisar " + AE01Cods(aRes[RES_QTDOUT]) + ;
                " com problema de quantidade ou de cadastro (coluna Motivo). "
    EndIf

    cTxt += "Falta de estrutura ou de roteiro trava o in&iacute;cio da " + ;
            "produ&ccedil;&atilde;o do item."

    aAdd(aHtm, '<div class="acao"><b>A&Ccedil;&Atilde;O NECESS&Aacute;RIA</b>' + cTxt + '</div>')

Return Nil


/*/{Protheus.doc} AE01Alerta
Secao de pontos a verificar: item bloqueado e revisao consultada diferente
da revisao atual do cadastro. Nao sao erros de engenharia, mas mudam a
leitura do relatorio, entao ficam em quadro proprio.

@param aHtm Array do HTML, alterado por referencia
@param aRes Array de resultado
@param nSec Numero da secao
/*/
Static Function AE01Alerta(aHtm, aRes, nSec)

    Local aAle := aRes[RES_ALERTAS]
    Local nI   := 0

    AE01Sec(aHtm, nSec, "PONTOS A VERIFICAR")

    aAdd(aHtm, '<table class="g">')
    aAdd(aHtm, '<colgroup><col style="width:16%"><col style="width:24%">')
    aAdd(aHtm, '<col style="width:6%"><col style="width:6%">')
    aAdd(aHtm, '<col style="width:28%"><col style="width:20%"></colgroup>')
    aAdd(aHtm, '<tr><th>C&oacute;digo</th><th>Descri&ccedil;&atilde;o</th>')
    aAdd(aHtm, '<th class="c">Tipo</th><th class="c">Ocorr.</th>')
    aAdd(aHtm, '<th>Motivo</th><th>C&oacute;digo pai</th></tr>')

    For nI := 1 To Len(aAle)
        aAdd(aHtm, '<tr' + IIf(nI % 2 == 0, ' class="alt"', '') + '>')
        aAdd(aHtm, '<td class="cod">' + AE01Esc(aAle[nI][ERR_CODIGO]) + '</td>')
        aAdd(aHtm, '<td class="dim">' + AE01Esc(aAle[nI][ERR_DESC]) + '</td>')
        aAdd(aHtm, '<td class="c">' + AE01Esc(aAle[nI][ERR_TIPO]) + '</td>')
        aAdd(aHtm, '<td class="c">' + cValToChar(aAle[nI][ERR_OCORR]) + '</td>')
        aAdd(aHtm, '<td class="dim">' + AE01Esc(aAle[nI][ERR_MOTIVO]) + '</td>')
        aAdd(aHtm, '<td class="dim">' + AE01Pais(aAle[nI][ERR_PAIS]) + '</td>')
        aAdd(aHtm, '</tr>')
    Next nI

    aAdd(aHtm, '</table>')

Return Nil


/*/{Protheus.doc} AE01Analis
Secao ANALISE DETALHADA: os dois quadros por tipo, cada um com a sua nota
de rodape explicando o criterio de contagem.

@param aHtm Array do HTML, alterado por referencia
@param aRes Array de resultado
@param nSec Numero da secao
/*/
Static Function AE01Analis(aHtm, aRes, nSec)

    Local aEst  := aRes[RES_TOTEST]
    Local aRot  := aRes[RES_TOTROT]

    Local nTot  := 0
    Local nOk   := 0
    Local nSem  := 0
    Local nUni  := 0
    Local nCom  := 0
    Local nSemR := 0
    Local nI    := 0

    AE01Sec(aHtm, nSec, "AN&Aacute;LISE DETALHADA")

    // ------------------------------------------------- quadro de estrutura
    aAdd(aHtm, '<table class="q qe">')
    aAdd(aHtm, '<colgroup><col style="width:12%"><col style="width:22%">')
    aAdd(aHtm, '<col style="width:22%"><col style="width:22%"><col style="width:22%"></colgroup>')
    aAdd(aHtm, '<tr><th class="cap" colspan="5">AN&Aacute;LISE DE ESTRUTURA</th></tr>')
    aAdd(aHtm, '<tr><th>TIPO</th><th>TOTAL</th><th>OK</th>')
    aAdd(aHtm, '<th>SEM ESTRUTURA</th><th>SITUA&Ccedil;&Atilde;O</th></tr>')

    For nI := 1 To Len(aEst)

        nTot += aEst[nI][TOT_TOTAL]
        nOk  += aEst[nI][TOT_OK]
        nSem += aEst[nI][TOT_SEMEST]

        aAdd(aHtm, '<tr' + IIf(nI % 2 == 0, ' class="alt"', '') + '>')
        aAdd(aHtm, '<td class="tp">' + AE01Esc(aEst[nI][TOT_TIPO]) + '</td>')
        aAdd(aHtm, '<td>' + cValToChar(aEst[nI][TOT_TOTAL]) + '</td>')
        aAdd(aHtm, '<td>' + cValToChar(aEst[nI][TOT_OK]) + '</td>')
        aAdd(aHtm, '<td' + IIf(aEst[nI][TOT_SEMEST] > 0, ' class="err"', ' class="na"') + '>' + ;
                   cValToChar(aEst[nI][TOT_SEMEST]) + '</td>')
        aAdd(aHtm, AE01Selo(IIf(aEst[nI][TOT_SEMEST] > 0, "ERRO", "OK")))
        aAdd(aHtm, '</tr>')

    Next nI

    aAdd(aHtm, '<tr class="tot"><td class="tp">TOTAL</td>')
    aAdd(aHtm, '<td>' + cValToChar(nTot) + '</td><td>' + cValToChar(nOk) + '</td>')
    aAdd(aHtm, '<td' + IIf(nSem > 0, ' style="color:' + COR_VERM + ';"', '') + '>' + ;
               cValToChar(nSem) + '</td>')
    aAdd(aHtm, '<td>&mdash;</td></tr>')
    aAdd(aHtm, '</table>')

    aAdd(aHtm, '<div class="obs obse"><b>Obs. &nbsp;Estrutura &nbsp;&middot;&nbsp;</b><span>' + ;
               'Contagem por ocorr&ecirc;ncia na &aacute;rvore completa: o mesmo ' + ;
               'c&oacute;digo usado em dois pais conta duas vezes. S&atilde;o folhas ' + ;
               'v&aacute;lidas MP, SV e os BN/EM sem estrutura vigente; os demais ' + ;
               'precisam descer at&eacute; uma delas.</span></div>')

    // --------------------------------------------------- quadro de roteiro
    aAdd(aHtm, '<table class="q qr">')
    aAdd(aHtm, '<colgroup><col style="width:12%"><col style="width:16%">')
    aAdd(aHtm, '<col style="width:16%"><col style="width:16%"><col style="width:20%">')
    aAdd(aHtm, '<col style="width:20%"></colgroup>')
    aAdd(aHtm, '<tr><th class="cap" colspan="6">AN&Aacute;LISE DE ROTEIRO</th></tr>')
    aAdd(aHtm, '<tr><th>TIPO</th><th>&Uacute;NICOS</th><th>COM ROTEIRO</th>')
    aAdd(aHtm, '<th>SEM ROTEIRO</th><th>EXIGE?</th><th>SITUA&Ccedil;&Atilde;O</th></tr>')

    For nI := 1 To Len(aRot)

        nUni  += aRot[nI][ROT_UNICOS]
        nCom  += aRot[nI][ROT_COM]
        nSemR += aRot[nI][ROT_SEM]

        aAdd(aHtm, '<tr' + IIf(nI % 2 == 0, ' class="alt"', '') + '>')
        aAdd(aHtm, '<td class="tp">' + AE01Esc(aRot[nI][ROT_TIPO]) + '</td>')
        aAdd(aHtm, '<td>' + cValToChar(aRot[nI][ROT_UNICOS]) + '</td>')
        aAdd(aHtm, '<td>' + cValToChar(aRot[nI][ROT_COM]) + '</td>')
        aAdd(aHtm, '<td>' + cValToChar(aRot[nI][ROT_SEM]) + '</td>')
        aAdd(aHtm, '<td class="dim">' + aRot[nI][ROT_EXIGE] + '</td>')
        aAdd(aHtm, AE01Selo(IIf(aRot[nI][ROT_ERRO] > 0, "ERRO", "OK")))
        aAdd(aHtm, '</tr>')

    Next nI

    aAdd(aHtm, '<tr class="tot"><td class="tp">TOTAL</td>')
    aAdd(aHtm, '<td>' + cValToChar(nUni) + '</td><td>' + cValToChar(nCom) + '</td>')
    aAdd(aHtm, '<td>' + cValToChar(nSemR) + '</td><td>&mdash;</td><td>&mdash;</td></tr>')
    aAdd(aHtm, '</table>')

    aAdd(aHtm, '<div class="obs obsr"><b>Obs. &nbsp;Roteiro &nbsp;&middot;&nbsp;</b><span>' + ;
               'Contagem por c&oacute;digo &uacute;nico. Vale qualquer opera&ccedil;&atilde;o ' + ;
               'em SG2 na filial ' + AE01Esc(aRes[RES_CAB][CAB_FILIAL]) + ', sem filtro de ' + ;
               'data. "SEM ROTEIRO" n&atilde;o &eacute; erro por si: MP e SV n&atilde;o ' + ;
               'exigem, EM/BN s&oacute; exigem quando t&ecirc;m estrutura e o PA ' + ;
               AUD_FINAME + '* &eacute; dispensado. A coluna SITUA&Ccedil;&Atilde;O ' + ;
               'considera s&oacute; quem exige e n&atilde;o tem.</span></div>')

Return Nil


/*/{Protheus.doc} AE01Regr
Secao CRITERIOS DE ANALISE, alimentada por AE01Criter().

@param aHtm    Array do HTML, alterado por referencia
@param nSec    Numero da secao
@param cFilial Filial auditada
/*/
Static Function AE01Regr(aHtm, nSec, cFilial)

    Local aCri := AE01Criter(cFilial)
    Local nI   := 0

    AE01Sec(aHtm, nSec, "CRIT&Eacute;RIOS DE AN&Aacute;LISE")

    aAdd(aHtm, '<table class="cri">')

    For nI := 1 To Len(aCri)

        If nI % 2 == 1
            aAdd(aHtm, '<tr' + IIf(Int((nI + 1) / 2) % 2 == 0, ' class="alt"', '') + '>')
        EndIf

        aAdd(aHtm, '<td><b>' + aCri[nI][1] + ' &mdash; </b>' + aCri[nI][2] + '</td>')

        If nI % 2 == 0 .Or. nI == Len(aCri)
            If nI % 2 == 1
                aAdd(aHtm, '<td></td>')
            EndIf
            aAdd(aHtm, '</tr>')
        EndIf

    Next nI

    aAdd(aHtm, '</table>')

Return Nil


/*/{Protheus.doc} AE01Arvore
Anexo opcional com a arvore completa, uma linha por componente.

E o retorno bruto da explosao, util para conferir um caminho especifico.
Fica limitado a AUD_MAXARV linhas para o HTML nao ficar impossivel de abrir
- o CSV analitico traz tudo.

@param aHtm Array do HTML, alterado por referencia
@param aRes Array de resultado
@param nSec Numero da secao
/*/
Static Function AE01Arvore(aHtm, aRes, nSec)

    Local aLin := aRes[RES_LINHAS]
    Local nQtd := Min(Len(aLin), AUD_MAXARV)
    Local nI   := 0

    AE01Sec(aHtm, nSec, "ANEXO &mdash; &Aacute;RVORE COMPLETA")

    aAdd(aHtm, '<table class="g">')
    aAdd(aHtm, '<tr><th class="c">N&iacute;vel</th><th>C&oacute;digo pai</th>')
    aAdd(aHtm, '<th>C&oacute;digo</th><th>Descri&ccedil;&atilde;o</th>')
    aAdd(aHtm, '<th class="c">Tipo</th><th class="c">UM</th><th class="c">Qtd.</th>')
    aAdd(aHtm, '<th class="c">Estrut.</th><th class="c">Roteiro</th>')
    aAdd(aHtm, '<th class="c">Situa&ccedil;&atilde;o</th><th>Motivo</th></tr>')

    For nI := 1 To nQtd
        aAdd(aHtm, '<tr' + IIf(nI % 2 == 0, ' class="alt"', '') + '>')
        aAdd(aHtm, '<td class="c">' + cValToChar(aLin[nI][LIN_NIVEL]) + '</td>')
        aAdd(aHtm, '<td class="dim">' + AE01Esc(aLin[nI][LIN_CODPAI]) + '</td>')
        aAdd(aHtm, '<td class="cod">' + AE01Esc(aLin[nI][LIN_CODIGO]) + '</td>')
        aAdd(aHtm, '<td class="dim">' + AE01Esc(aLin[nI][LIN_DESC]) + '</td>')
        aAdd(aHtm, '<td class="c">' + AE01Esc(aLin[nI][LIN_TIPO]) + '</td>')
        aAdd(aHtm, '<td class="c">' + AE01Esc(aLin[nI][LIN_UM]) + '</td>')
        aAdd(aHtm, '<td class="r">' + AE01Num(aLin[nI][LIN_QUANT]) + '</td>')
        aAdd(aHtm, '<td class="c">' + IIf(aLin[nI][LIN_TEMEST], "S", "N") + '</td>')
        aAdd(aHtm, '<td class="c">' + IIf(aLin[nI][LIN_TEMROT], "S", "N") + '</td>')
        aAdd(aHtm, AE01Selo(aLin[nI][LIN_SITUACAO]))
        aAdd(aHtm, '<td class="dim">' + AE01Esc(aLin[nI][LIN_MOTIVO]) + '</td>')
        aAdd(aHtm, '</tr>')
    Next nI

    aAdd(aHtm, '</table>')

    If nQtd < Len(aLin)
        aAdd(aHtm, '<div class="obs obse"><b>Anexo truncado &nbsp;&middot;&nbsp;</b><span>' + ;
                   'exibindo ' + cValToChar(nQtd) + ' de ' + cValToChar(Len(aLin)) + ' linhas. ' + ;
                   'O CSV anal&iacute;tico traz a &aacute;rvore inteira.</span></div>')
    EndIf

Return Nil


/*/{Protheus.doc} AE01Rodape
Fecha o HTML com a identificacao de quem gerou e de onde vieram os dados.

@param aHtm Array do HTML, alterado por referencia
@param aCfg Array de configuracao
@param aRes Array de resultado
/*/
Static Function AE01Rodape(aHtm, aCfg, aRes)

    aAdd(aHtm, '<div class="pe">')
    aAdd(aHtm, 'zAudEst ' + AUD_VERSAO + ' &nbsp;&middot;&nbsp; ' + ;
               cValToChar(Len(aRes[RES_LINHAS])) + ' linhas explodidas at&eacute; o ' + ;
               'n&iacute;vel ' + cValToChar(aCfg[CFG_NIVEL]) + ' &nbsp;&middot;&nbsp; ')
    aAdd(aHtm, 'SB1 / SG1 / SG2 da filial ' + AE01Esc(aCfg[CFG_FILIAL]) + ' &nbsp;&middot;&nbsp; ')
    aAdd(aHtm, 'vig&ecirc;ncia da estrutura em ' + DToC(Date()) + ' &nbsp;&middot;&nbsp; ')
    aAdd(aHtm, 'gerado por ' + AE01Esc(AllTrim(cUserName)) + ' em ' + ;
               DToC(Date()) + ' &agrave;s ' + Time())
    aAdd(aHtm, '</div>')
    aAdd(aHtm, '</div>')
    aAdd(aHtm, '</body>')
    aAdd(aHtm, '</html>')

Return Nil


// ===========================================================================
// AUXILIARES DO HTML
// ===========================================================================

/*/{Protheus.doc} AE01Sec
Barra escura de titulo de secao, com o numero em destaque.

@param aHtm    Array do HTML, alterado por referencia
@param nSec    Numero da secao
@param cTitulo Titulo (ja em HTML)
/*/
Static Function AE01Sec(aHtm, nSec, cTitulo)
    aAdd(aHtm, '<div class="sec"><i>' + cValToChar(nSec) + '</i>' + cTitulo + '</div>')
Return Nil


/*/{Protheus.doc} AE01Card
Cartao de contagem. Vermelho quando ha ocorrencia, verde quando esta zerado.

@param aHtm   Array do HTML, alterado por referencia
@param nQtd   Quantidade
@param cTitulo Titulo do cartao (ja em HTML)
@param cSub   Legenda do cartao (ja em HTML)
/*/
Static Function AE01Card(aHtm, nQtd, cTitulo, cSub)

    Local cFundo := IIf(nQtd > 0, COR_FDVERM, COR_FDVERD2)
    Local cCor   := IIf(nQtd > 0, COR_VERM  , COR_VERDE)

    aAdd(aHtm, '<td style="background:' + cFundo + ';">')
    aAdd(aHtm, '<span class="n" style="color:' + cCor + ';">' + AE01Zero(nQtd) + '</span>')
    aAdd(aHtm, '<span class="t">' + cTitulo + '</span>')
    aAdd(aHtm, '<span class="s">' + cSub + '</span></td>')

Return Nil


/*/{Protheus.doc} AE01Selo
Celula colorida de situacao: OK verde, ERRO vermelho, VERIFICAR ambar e
"-" cinza para a regra que nem se aplica ao tipo.

@param cSit  OK / ERRO / VERIFICAR / -
@return cRet Celula <td> pronta
/*/
Static Function AE01Selo(cSit)

    Local cCls := "na"

    Do Case
        Case cSit == "OK"
            cCls := "ok"
        Case cSit == "ERRO"
            cCls := "err"
        Case cSit == "VERIFICAR"
            cCls := "ver"
    EndCase

Return '<td class="' + cCls + '">' + cSit + '</td>'


/*/{Protheus.doc} AE01Pais
Monta a lista de codigos pai de um componente, com o nivel em que a ligacao
acontece. Mostra ate AUD_MAXPAI e resume o excedente.

@param aPais Array de {cPai, nNivel}
@return cRet Texto em HTML
/*/
Static Function AE01Pais(aPais)

    Local cRet := ""
    Local nQtd := Min(Len(aPais), AUD_MAXPAI)
    Local nI   := 0

    For nI := 1 To nQtd
        cRet += IIf(nI > 1, "<br>", "") + AE01Esc(aPais[nI][1]) + ;
                " (n." + cValToChar(aPais[nI][2]) + ")"
    Next nI

    If Len(aPais) > nQtd
        cRet += "<br>+ " + cValToChar(Len(aPais) - nQtd) + " outro(s)"
    EndIf

    If Empty(cRet)
        cRet := "&mdash;"
    EndIf

Return cRet


/*/{Protheus.doc} AE01Esc
Escapa o conteudo vindo do banco para nao quebrar o HTML. O & precisa ser
trocado primeiro, senao as proprias entidades geradas aqui seriam escapadas
de novo.

@param cTexto Conteudo original
@return cRet  Conteudo seguro
/*/
Static Function AE01Esc(cTexto)

    Local cRet := ""

    If ValType(cTexto) != "C"
        Return cValToChar(cTexto)
    EndIf

    cRet := AllTrim(cTexto)
    cRet := StrTran(cRet, "&", "&amp;")
    cRet := StrTran(cRet, "<", "&lt;")
    cRet := StrTran(cRet, ">", "&gt;")
    cRet := StrTran(cRet, AUD_ASPA, "&quot;")

Return cRet


/*/{Protheus.doc} AE01Zero
Numero do cartao no formato do documento modelo (02, 01, 15).

@param nQtd  Quantidade
@return cRet Texto formatado
/*/
Static Function AE01Zero(nQtd)
Return IIf(nQtd < 100, StrZero(nQtd, 2), cValToChar(nQtd))


/*/{Protheus.doc} AE01Cods
Concordancia de "codigo/codigos" nos textos do relatorio.

@param nQtd  Quantidade
@return cRet Texto em HTML
/*/
Static Function AE01Cods(nQtd)
Return cValToChar(nQtd) + IIf(nQtd == 1, " c&oacute;digo", " c&oacute;digos")


/*/{Protheus.doc} AE01Num
Formata quantidade no padrao brasileiro e tira os zeros a direita, para a
arvore nao ficar cheia de "1,000000".

@param nVal  Valor
@return cRet Texto formatado
/*/
Static Function AE01Num(nVal)

    Local cRet := AllTrim(Transform(nVal, "@E 999,999,999.999999"))

    Do While At(",", cRet) > 0 .And. Right(cRet, 1) == "0"
        cRet := SubStr(cRet, 1, Len(cRet) - 1)
    EndDo

    If Right(cRet, 1) == ","
        cRet := SubStr(cRet, 1, Len(cRet) - 1)
    EndIf

Return cRet


/*/{Protheus.doc} AE01Nome
Deixa o codigo do produto utilizavel como parte do nome de arquivo.

@param cCod  Codigo do produto
@return cRet Texto sem caracteres proibidos
/*/
Static Function AE01Nome(cCod)

    Local cRet := AllTrim(cCod)
    Local cInv := '\/:*?"<>| .,;'
    Local nI   := 0

    For nI := 1 To Len(cInv)
        cRet := StrTran(cRet, SubStr(cInv, nI, 1), "_")
    Next nI

    If Empty(cRet)
        cRet := "ITEM"
    EndIf

Return cRet


// ===========================================================================
// CSV ANALITICO, RESULTADO EM TELA E UTILITARIOS
// ===========================================================================

/*/{Protheus.doc} AE01Csv
Gera o CSV com a arvore inteira, uma linha por componente, incluindo as
colunas calculadas. E o arquivo para conferir no Excel ou reprocessar.

@param aCfg  Array de configuracao
@param aRes  Array de resultado
@return cArq Caminho do CSV no servidor ("" em caso de falha)
/*/
Static Function AE01Csv(aCfg, aRes)

    Local aLin := aRes[RES_LINHAS]
    Local cDir := aCfg[CFG_DIRREL]
    Local cArq := ""
    Local cAux := ""
    Local nHdl := 0
    Local nI   := 0

    If Right(cDir, 1) != "\"
        cDir += "\"
    EndIf

    AE01MkDir(cDir)

    cArq := cDir + "AUDEST_" + AE01Nome(aRes[RES_CAB][CAB_CODIGO]) + "_" + ;
            DToS(Date()) + "_" + StrTran(Time(), ":", "") + ".csv"

    nHdl := FCreate(cArq)

    If nHdl == -1
        ConOut("[zAudEst] Nao foi possivel criar o CSV: " + cArq + ;
               " (FError " + cValToChar(FError()) + ")")
        Return ""
    EndIf

    // Sem o BOM o Excel abre o CSV UTF-8 como ANSI e quebra a acentuacao
    If aCfg[CFG_CODIF] == 2
        FWrite(nHdl, Chr(239) + Chr(187) + Chr(191))
    EndIf

    FWrite(nHdl, "NIVEL;COD_PAI;CODIGO;DESCRICAO;TIPO;UM;QUANTIDADE;BLOQUEADO;" + ;
                 "TEM_ESTRUTURA;TEM_ROTEIRO;TEM_FILHO;ERRO_ESTRUTURA;ERRO_ROTEIRO;" + ;
                 "SITUACAO;MOTIVO;REV_CONSULTADA;REV_ATUAL;CAMINHO" + CRLF)

    For nI := 1 To Len(aLin)

        cAux := cValToChar(aLin[nI][LIN_NIVEL])                    + ";" + ;
                AE01Cel(aLin[nI][LIN_CODPAI])                      + ";" + ;
                AE01Cel(aLin[nI][LIN_CODIGO])                      + ";" + ;
                AE01Cel(aLin[nI][LIN_DESC])                        + ";" + ;
                AE01Cel(aLin[nI][LIN_TIPO])                        + ";" + ;
                AE01Cel(aLin[nI][LIN_UM])                          + ";" + ;
                AE01Num(aLin[nI][LIN_QUANT])                       + ";" + ;
                IIf(aLin[nI][LIN_BLOQ]    , "S", "N")              + ";" + ;
                IIf(aLin[nI][LIN_TEMEST]  , "S", "N")              + ";" + ;
                IIf(aLin[nI][LIN_TEMROT]  , "S", "N")              + ";" + ;
                IIf(aLin[nI][LIN_TEMFILHO], "S", "N")              + ";" + ;
                IIf(aLin[nI][LIN_ERREST]  , "S", "N")              + ";" + ;
                IIf(aLin[nI][LIN_ERRROT]  , "S", "N")              + ";" + ;
                AE01Cel(aLin[nI][LIN_SITUACAO])                    + ";" + ;
                AE01Cel(aLin[nI][LIN_MOTIVO])                      + ";" + ;
                AE01Cel(aLin[nI][LIN_REVCON])                      + ";" + ;
                AE01Cel(aLin[nI][LIN_REVATU])                      + ";" + ;
                AE01Cel(aLin[nI][LIN_CAMINHO])

        If aCfg[CFG_CODIF] == 2
            cAux := EncodeUTF8(cAux)
        EndIf

        FWrite(nHdl, cAux + CRLF)

    Next nI

    FClose(nHdl)

Return cArq


/*/{Protheus.doc} AE01Cel
Prepara o conteudo para uma celula do CSV: aspas em volta e aspas internas
removidas, para descricao com ponto-e-virgula nao quebrar a coluna.

@param cTexto Conteudo original
@return cRet  Celula pronta
/*/
Static Function AE01Cel(cTexto)
Return AUD_ASPA + StrTran(AllTrim(cTexto), AUD_ASPA, "") + AUD_ASPA


/*/{Protheus.doc} AE01Ver
Mostra o resultado em tela, com o resumo, o browse dos erros e o dos pontos
a verificar.

O browse existe porque quem usa a rotina normalmente nao tem acesso a pasta
de relatorios do servidor - assim ele ja enxerga o que precisa corrigir sem
depender de nenhum arquivo.

@param aCfg    Array de configuracao
@param aRes    Array de resultado
@param cArqHtm Caminho do HTML no servidor
@param cArqCsv Caminho do CSV no servidor
@param cAviso  Aviso de falha na copia para a estacao ("" quando tudo ok)
@param nSeg    Tempo total de processamento, em segundos
/*/
Static Function AE01Ver(aCfg, aRes, cArqHtm, cArqCsv, cAviso, nSeg)

    Local oDlg
    Local oFolder
    Local oMemRes
    Local oBrwErr
    Local oBrwAle
    Local oPnlErr
    Local oPnlAle

    Local aErr    := aRes[RES_ERROS]
    Local aAle    := aRes[RES_ALERTAS]

    Local nTotal  := aRes[RES_QTDEST] + aRes[RES_QTDROT] + aRes[RES_QTDOUT]
    Local cResumo := ""

    Local aAbas   := {"Erros (" + cValToChar(Len(aErr)) + ")", ;
                      "Verificar (" + cValToChar(Len(aAle)) + ")"}

    cResumo := "Produto..............: " + aRes[RES_CAB][CAB_CODIGO] + " - " + ;
                                           aRes[RES_CAB][CAB_DESC] + CRLF + ;
               "Tipo / revisao.......: " + aRes[RES_CAB][CAB_TIPO] + " / " + ;
                                           aRes[RES_CAB][CAB_REVISAO] + ;
                                           " (atual no cadastro: " + aRes[RES_CAB][CAB_REVATU] + ")" + CRLF + ;
               "Filial / nivel.......: " + aCfg[CFG_FILIAL] + " / ate " + ;
                                           cValToChar(aCfg[CFG_NIVEL]) + CRLF + ;
               "Linhas explodidas....: " + cValToChar(Len(aRes[RES_LINHAS])) + ;
                                           "   (em " + AE01Num(Round(nSeg, 1)) + " segundos)" + CRLF + ;
               Replicate("-", 70) + CRLF + ;
               "Erros de estrutura...: " + cValToChar(aRes[RES_QTDEST]) + " codigo(s)" + CRLF + ;
               "Erros de roteiro.....: " + cValToChar(aRes[RES_QTDROT]) + " codigo(s)" + CRLF + ;
               "Quantidade/cadastro..: " + cValToChar(aRes[RES_QTDOUT]) + " codigo(s)" + CRLF + ;
               "TOTAL DE ERROS.......: " + cValToChar(nTotal) + CRLF + ;
               "Pontos a verificar...: " + cValToChar(Len(aAle)) + CRLF + ;
               Replicate("-", 70) + CRLF + ;
               "Relatorio (servidor).: " + cArqHtm + CRLF + ;
               IIf(Empty(cArqCsv), "", "CSV analitico........: " + cArqCsv + CRLF) + ;
               IIf(Empty(aCfg[CFG_DIREST]), "", ;
                   "Copia na estacao.....: " + aCfg[CFG_DIREST] + CRLF) + ;
               IIf(Empty(cAviso), "", CRLF + "ATENCAO: " + cAviso + CRLF)

    DEFINE MSDIALOG oDlg TITLE "Auditoria de Roteiro / Estrutura - resultado" ;
           FROM 0, 0 TO 490, 800 PIXEL

    @ 006, 005 SAY "Resumo:" SIZE 100, 08 PIXEL OF oDlg
    @ 016, 005 GET oMemRes VAR cResumo MEMO SIZE 385, 070 PIXEL OF oDlg
    oMemRes:lReadOnly := .T.

    oFolder := TFolder():New(092, 005, aAbas, {}, oDlg, , , , .T., .F., 385, 120)

    oPnlErr := oFolder:aDialogs[1]
    oPnlAle := oFolder:aDialogs[2]

    // ---------------------------------------------------- aba 1: erros
    If Len(aErr) == 0
        @ 010, 010 SAY "Nenhum erro encontrado. A estrutura desce ate folha valida " + ;
                       "e o roteiro esta cadastrado onde e exigido." ;
                    SIZE 350, 10 PIXEL OF oPnlErr
    Else
        @ 005, 005 LISTBOX oBrwErr FIELDS HEADER "Codigo", "Tipo", "Ocor.", ;
                   "Estrut.", "Roteiro", "Motivo" ;
                   SIZE 372, 098 PIXEL OF oPnlErr
        oBrwErr:SetArray(aErr)
        oBrwErr:bLine := {|| {PadR(aErr[oBrwErr:nAt][ERR_CODIGO], 20)          , ;
                              PadR(aErr[oBrwErr:nAt][ERR_TIPO]  , 04)          , ;
                              StrZero(aErr[oBrwErr:nAt][ERR_OCORR], 4)         , ;
                              PadR(aErr[oBrwErr:nAt][ERR_EST]   , 06)          , ;
                              PadR(aErr[oBrwErr:nAt][ERR_ROT]   , 06)          , ;
                              aErr[oBrwErr:nAt][ERR_MOTIVO]                    } }
    EndIf

    // ------------------------------------------------ aba 2: verificar
    If Len(aAle) == 0
        @ 010, 010 SAY "Nenhum ponto a verificar." SIZE 350, 10 PIXEL OF oPnlAle
    Else
        @ 005, 005 LISTBOX oBrwAle FIELDS HEADER "Codigo", "Tipo", "Ocor.", "Motivo" ;
                   SIZE 372, 098 PIXEL OF oPnlAle
        oBrwAle:SetArray(aAle)
        oBrwAle:bLine := {|| {PadR(aAle[oBrwAle:nAt][ERR_CODIGO], 20)          , ;
                              PadR(aAle[oBrwAle:nAt][ERR_TIPO]  , 04)          , ;
                              StrZero(aAle[oBrwAle:nAt][ERR_OCORR], 4)         , ;
                              aAle[oBrwAle:nAt][ERR_MOTIVO]                    } }
    EndIf

    // ------------------------------------------------------------- rodape
    TButton():New(220, 005, "Salvar relatorio na minha maquina", oDlg, ;
                  {|| AE01Salvar(cArqHtm, cArqCsv) }, ;
                  120, 013, , , .F., .T., .F., , .F., , , .F.)

    TButton():New(220, 340, "Fechar", oDlg, {|| oDlg:End() }, ;
                  050, 013, , , .F., .T., .F., , .F., , , .F.)

    ACTIVATE MSDIALOG oDlg CENTERED

Return Nil


/*/{Protheus.doc} AE01Salvar
Copia o relatorio (e o CSV, quando existe) para uma pasta escolhida na
maquina do usuario.

@param cArqHtm Caminho do HTML no servidor
@param cArqCsv Caminho do CSV no servidor
/*/
Static Function AE01Salvar(cArqHtm, cArqCsv)

    Local cDir := ""

    If Empty(cArqHtm) .Or. !File(cArqHtm)
        MsgInfo("Nao ha relatorio para salvar.", "Salvar relatorio")
        Return Nil
    EndIf

    cDir := cGetFile("", "Escolha a pasta de destino na sua maquina", 0, ;
                     "", .F., GETF_LOCALHARD + GETF_RETDIRECTORY, .F., .F.)

    If Empty(cDir)
        Return Nil
    EndIf

    If AE01Baixar(cArqHtm, cDir)
        If !Empty(cArqCsv) .And. File(cArqCsv)
            AE01Baixar(cArqCsv, cDir)
        EndIf
        MsgInfo("Relatorio salvo em:" + CRLF + CRLF + AllTrim(cDir), "Concluido")
    Else
        MsgStop("Nao foi possivel salvar o relatorio em:" + CRLF + AllTrim(cDir) + CRLF + CRLF + ;
                "Verifique se a pasta existe e se voce tem permissao de escrita nela.", ;
                "Salvar relatorio")
    EndIf

Return Nil


/*/{Protheus.doc} AE01Baixar
Copia um arquivo gerado no servidor para uma pasta na maquina do usuario.

FCreate/FWrite sempre gravam no AppServer, entao o relatorio nasce no
servidor. CpyS2T() e a funcao documentada para leva-lo ate a estacao (o
segundo parametro e o DIRETORIO de destino, nao o nome do arquivo).

A pasta precisa existir na estacao - MakeDir criaria no servidor, nao la.
No SmartClient HTML o navegador trata a transferencia como download e pode
salvar na pasta de downloads do browser, ignorando o caminho informado.

@param cArqServ Caminho completo do arquivo no servidor
@param cDirEsta Diretorio de destino na estacao
@return lOk     .T. quando a copia foi concluida
/*/
Static Function AE01Baixar(cArqServ, cDirEsta)

    Local lOk  := .F.
    Local cDir := AllTrim(cDirEsta)

    If Empty(cArqServ) .Or. Empty(cDir) .Or. !File(cArqServ)
        Return .F.
    EndIf

    // CpyS2T espera o diretorio sem a barra final
    If Right(cDir, 1) == "\"
        cDir := SubStr(cDir, 1, Len(cDir) - 1)
    EndIf

    lOk := CpyS2T(cArqServ, cDir, .T.)

Return lOk


/*/{Protheus.doc} AE01MkDir
Cria o diretorio no servidor quando ele ainda nao existe.

@param cDir Diretorio a criar
/*/
Static Function AE01MkDir(cDir)

    Local cAux := AllTrim(cDir)

    If Right(cAux, 1) != "\"
        cAux += "\"
    EndIf

    If !ExistDir(cAux)
        MakeDir(cAux)
    EndIf

Return Nil
