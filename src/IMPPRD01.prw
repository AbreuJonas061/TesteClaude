#Include "Protheus.ch"
#Include "FileIO.ch"
#Include "Set.ch"

/* ===========================================================================
   zImpPro - Importacao de Produtos (SB1/SB5) via ExecAuto

   Protheus 12.1.2410 / SmartClient HTML (navegador).

   A gravacao e feita exclusivamente por MSExecAuto, entao todo produto passa
   pelas validacoes nativas do cadastro. Sao duas rotinas automaticas, na
   mesma transacao: MATA010 para o produto (SB1) e MATA180 para o complemento
   (SB5) - no 12.1.2410 o MATA010 e MVC e nao aceita campos B5_ no seu array.

   O arquivo (CSV ou TXT) precisa ter a PRIMEIRA LINHA com os nomes tecnicos
   dos campos. Para importar um campo novo basta acrescentar a coluna - nao e
   necessario recompilar.

   Separador e codificacao sao detectados automaticamente.

   Manutencao: IP01Fixos(), logo abaixo, e o unico ponto que normalmente
   precisa ser alterado.
   =========================================================================== */

#DEFINE IMP_VERSAO   "2.00"
#DEFINE IMP_DIRLOG   "\imp_produtos\log\"
#DEFINE IMP_DIREST   "C:\Erros Protheus"   // copia do log na maquina do usuario
#DEFINE IMP_TAB      Chr(9)
#DEFINE IMP_ASPA     Chr(34)
#DEFINE IMP_BOM      Chr(239) + Chr(187) + Chr(191)

// Posicoes do array de resultado
#DEFINE RES_ARQUIVO  1
#DEFINE RES_LIDAS    2
#DEFINE RES_INCLUIU  3
#DEFINE RES_ALTEROU  4
#DEFINE RES_IGNOROU  5
#DEFINE RES_ERROS    6
#DEFINE RES_REJEIT   7
#DEFINE RES_COLUNAS  8
#DEFINE RES_DESCARTA 9
#DEFINE RES_FATAL    10
#DEFINE RES_SIZE     10

// Posicoes de cada linha rejeitada
#DEFINE REJ_LINHA    1
#DEFINE REJ_PRODUTO  2
#DEFINE REJ_MOTIVO   3
#DEFINE REJ_DETALHE  4    // log bruto do ExecAuto, so vai para o arquivo

#DEFINE IMP_MAXDET   2000 // limite do log bruto guardado por linha


/*/{Protheus.doc} zImpPro
Importacao de produtos. Cadastro no menu: U_zImpPro / Funcao Protheus.
/*/
User Function zImpPro()

    Local aArea := FWGetArea()

    IP01MkDir(IMP_DIRLOG)
    IP01Tela()

    FWRestArea(aArea)

Return Nil


/*/{Protheus.doc} IP01Fixos
Valores aplicados a todos os produtos, quando a coluna nao vem preenchida
no arquivo. O conteudo do arquivo sempre tem prioridade.

Use para campos obrigatorios que nunca variam na carga.

@return aFix Array de {cCampo, xValor}
/*/
Static Function IP01Fixos()

    Local aFix := {}

    aAdd(aFix, {"B1_MSBLQL", "2"})    // produto liberado

    // Exemplos:
    // aAdd(aFix, {"B1_LOCPAD", "01"})
    // aAdd(aFix, {"B1_SEGUM" , "UN"})

Return aFix


/*/{Protheus.doc} IP01Copia
Campos preenchidos com o conteudo de outro campo do mesmo produto.

Evita repetir a mesma informacao em duas colunas da planilha. So valem
para campos texto, e o conteudo e truncado no tamanho do destino quando
necessario. Uma coluna vinda do arquivo sempre tem prioridade sobre a
copia.

@return aCop Array de {cDestino, cOrigem}
/*/
Static Function IP01Copia()

    Local aCop := {}

    //         Destino     Origem
    aAdd(aCop, {"B5_COD"  , "B1_COD" })    // chave do complemento
    aAdd(aCop, {"B5_CEME" , "B1_DESC"})

Return aCop


// ===========================================================================
// TELA
// ===========================================================================

Static Function IP01Tela()

    Local oDlg, oGet, oChk1, oChk2
    Local cArquivo := Space(250)
    Local lSimula  := .T.
    Local lAtualiz := .F.

    DEFINE MSDIALOG oDlg TITLE "Importacao de Produtos - v" + IMP_VERSAO ;
           FROM 0, 0 TO 150, 600 PIXEL

    @ 010, 010 SAY "Arquivo:" SIZE 040, 09 PIXEL OF oDlg
    @ 009, 050 MSGET oGet VAR cArquivo SIZE 175, 10 PIXEL OF oDlg

    TButton():New(009, 230, "...", oDlg, ;
                  {|| cArquivo := IP01Busca(cArquivo), oGet:Refresh() }, ;
                  025, 011, , , .F., .T., .F., , .F., , , .F.)

    @ 028, 012 CHECKBOX oChk1 VAR lSimula ;
               PROMPT "Somente simular - conferir o arquivo sem gravar" ;
               SIZE 230, 09 PIXEL OF oDlg

    @ 040, 012 CHECKBOX oChk2 VAR lAtualiz ;
               PROMPT "Atualizar produtos que ja existem" ;
               SIZE 230, 09 PIXEL OF oDlg

    TButton():New(058, 130, "Importar", oDlg, ;
                  {|| IP01Importa(cArquivo, lSimula, lAtualiz) }, ;
                  060, 014, , , .F., .T., .F., , .F., , , .F.)

    TButton():New(058, 195, "Sair", oDlg, {|| oDlg:End() }, ;
                  060, 014, , , .F., .T., .F., , .F., , , .F.)

    ACTIVATE MSDIALOG oDlg CENTERED

Return Nil


/*/{Protheus.doc} IP01Busca
Selecao do arquivo na maquina do usuario.

No SmartClient HTML o proprio cGetFile transfere o arquivo para o servidor
e devolve um caminho ja legivel pelo AppServer. No SmartClient desktop o
caminho e da estacao e precisa ser trazido por CpyT2S.
/*/
Static Function IP01Busca(cAtual)

    Local cRet := AllTrim(cAtual)
    Local cArq := cGetFile("Arquivos CSV e TXT|*.csv;*.txt|Todos|*.*", ;
                           "Selecione o arquivo de produtos", 0, "", .F., ;
                           GETF_LOCALHARD, .F., .F.)

    If Empty(cArq)
        Return PadR(cRet, 250)
    EndIf

    If File(cArq)                       // AppServer ja enxerga
        Return PadR(cArq, 250)
    EndIf

    IP01MkDir(IMP_DIRLOG)

    If CpyT2S(cArq, IMP_DIRLOG, .F.)
        cRet := IMP_DIRLOG + IP01NmArq(cArq)
    Else
        MsgStop("Nao foi possivel enviar o arquivo para o servidor.", "Atencao")
    EndIf

Return PadR(cRet, 250)


// ===========================================================================
// PROCESSAMENTO
// ===========================================================================

Static Function IP01Importa(cArquivo, lSimula, lAtualiz)

    Local aRes  := {}
    Local cArq  := AllTrim(cArquivo)

    If Empty(cArq)
        MsgStop("Selecione o arquivo pelo botao '...'.", "Atencao")
        Return Nil
    EndIf

    If !File(cArq)
        MsgStop("Arquivo nao encontrado:" + CRLF + cArq, "Atencao")
        Return Nil
    EndIf

    If !lSimula .And. !MsgYesNo("Confirma a GRAVACAO dos produtos deste arquivo?" + ;
                                CRLF + CRLF + cArq, "Confirmacao")
        Return Nil
    EndIf

    Processa({|| aRes := IP01Proc(cArq, lSimula, lAtualiz) }, "Importando...")

    If !Empty(aRes)
        IP01Result(aRes, lSimula)
    EndIf

Return Nil


/*/{Protheus.doc} IP01Proc
Le o arquivo e grava os produtos pelo ExecAuto.

@return aRes Array com o resultado (defines RES_*)
/*/
Static Function IP01Proc(cArq, lSimula, lAtualiz)

    Local aArea   := FWGetArea()
    Local aRes    := Array(RES_SIZE)
    Local aLinhas := {}
    Local aMapa   := {}
    Local aCampos := {}
    Local aIgnora := {}
    Local aRetLin := {}
    Local aCopia  := IP01PrepCop()

    Local cSepar  := ""
    Local cErro   := ""
    Local cCod    := ""
    Local cCodTdo := "|"

    Local nI      := 0
    Local nPos    := 0
    Local nOpc    := 0
    Local nRecDel := 0
    Local nTamCod := TamSX3("B1_COD")[1]

    Local lExiste := .F.

    aRes[RES_ARQUIVO]  := cArq
    aRes[RES_LIDAS]    := 0
    aRes[RES_INCLUIU]  := 0
    aRes[RES_ALTEROU]  := 0
    aRes[RES_IGNOROU]  := 0
    aRes[RES_ERROS]    := 0
    aRes[RES_REJEIT]   := {}
    aRes[RES_COLUNAS]  := ""
    aRes[RES_DESCARTA] := ""
    aRes[RES_FATAL]    := ""

    // ------------------------------------------------------------- leitura
    aLinhas := IP01LerArq(cArq, @cErro)

    If !Empty(cErro)
        aRes[RES_FATAL] := cErro
        FWRestArea(aArea)
        Return aRes
    EndIf

    If Len(aLinhas) < 2
        aRes[RES_FATAL] := "O arquivo tem " + cValToChar(Len(aLinhas)) + " linha(s). " + ;
                         "Sao necessarias pelo menos duas: o cabecalho com os nomes " + ;
                         "dos campos e uma linha de produto."
        FWRestArea(aArea)
        Return aRes
    EndIf

    cSepar := IP01Separ(aLinhas[1])
    aMapa  := IP01Mapa(aLinhas[1], cSepar, @aIgnora, @cErro)

    If !Empty(cErro)
        aRes[RES_FATAL] := cErro
        FWRestArea(aArea)
        Return aRes
    EndIf

    aRes[RES_COLUNAS] := IP01Lista(aMapa)

    If Len(aIgnora) > 0
        aRes[RES_DESCARTA] := IP01Junta(aIgnora)
    EndIf

    ProcRegua(Len(aLinhas) - 1)

    DbSelectArea("SB1")
    SB1->(DbSetOrder(1))

    // --------------------------------------------------------- linha a linha
    For nI := 2 To Len(aLinhas)

        IncProc("Linha " + cValToChar(nI) + " de " + cValToChar(Len(aLinhas)))

        If Empty(AllTrim(StrTran(aLinhas[nI], cSepar, "")))
            Loop
        EndIf

        aRes[RES_LIDAS]++

        cErro   := ""
        aCampos := IP01Reg(aLinhas[nI], cSepar, aMapa, aCopia, @cErro)

        If !Empty(cErro)
            IP01Rejeita(aRes, nI, "", cErro)
            Loop
        EndIf

        nPos := aScan(aCampos, {|x| x[1] == "B1_COD"})

        If nPos == 0 .Or. Empty(aCampos[nPos][2])
            IP01Rejeita(aRes, nI, "", "Codigo do produto (B1_COD) nao informado.")
            Loop
        EndIf

        cCod := PadR(aCampos[nPos][2], nTamCod)

        If ("|" + AllTrim(cCod) + "|") $ cCodTdo
            IP01Rejeita(aRes, nI, AllTrim(cCod), ;
                        "Codigo repetido dentro do proprio arquivo.")
            Loop
        EndIf
        cCodTdo += AllTrim(cCod) + "|"

        lExiste := SB1->(DbSeek(xFilial("SB1") + cCod))

        If lExiste .And. !lAtualiz
            aRes[RES_IGNOROU]++
            Loop
        EndIf

        // A exclusao no Protheus e logica: o DbSeek nao ve o registro, mas a
        // chave segue ocupada no indice e a inclusao seria recusada adiante
        // com "Item ja existe", sem indicar a causa.
        If !lExiste
            nRecDel := IP01RecDel(cCod)
            If nRecDel > 0
                IP01Rejeita(aRes, nI, AllTrim(cCod), ;
                            "Este codigo pertence a um produto EXCLUIDO (registro " + ;
                            cValToChar(nRecDel) + "). Use outro codigo.")
                Loop
            EndIf
        EndIf

        nOpc := IIf(lExiste, 4, 3)

        If lSimula
            If nOpc == 3
                aRes[RES_INCLUIU]++
            Else
                aRes[RES_ALTEROU]++
            EndIf
            Loop
        EndIf

        aRetLin := IP01Exec(aCampos, nOpc, cCod)

        If aRetLin[1]
            If nOpc == 3
                aRes[RES_INCLUIU]++
            Else
                aRes[RES_ALTEROU]++
            EndIf
        Else
            IP01Rejeita(aRes, nI, AllTrim(cCod), aRetLin[2], aRetLin[3])
        EndIf

    Next nI

    FWRestArea(aArea)

Return aRes


/*/{Protheus.doc} IP01Rejeita
Registra uma linha rejeitada no resultado.
/*/
Static Function IP01Rejeita(aRes, nLinha, cProduto, cMotivo, cDetalhe)

    Default cDetalhe := ""

    aRes[RES_ERROS]++
    aAdd(aRes[RES_REJEIT], {nLinha, cProduto, cMotivo, cDetalhe})

Return Nil


/*/{Protheus.doc} IP01Exec
Grava o produto e o complemento, cada um pela sua rotina automatica.

No 12.1.2410 o MATA010 e MVC e seu modelo so conhece campos de SB1 -
enviar um campo B5_ ali resulta em "O id de formulario 'B5_xxx' nao e
valido". O complemento tem rotina propria, MATA180, e por isso os campos
sao separados por prefixo e gravados em duas chamadas.

As duas ficam na mesma transacao: se o complemento falhar, o produto
tambem e desfeito, evitando SB1 sem o SB5 correspondente.

@param nOpc 3 = inclusao / 4 = alteracao (do produto)
@return aRet {lOk, cErro}
/*/
Static Function IP01Exec(aCampos, nOpc, cCod)

    Local aRet     := {.T., "", ""}
    Local aProduto := {}
    Local aCompl   := {}
    Local cFunOld  := FunName()
    Local cBruto   := ""
    Local nI       := 0
    Local nOpcB5   := 3

    Private lMsErroAuto    := .F.
    Private lMsHelpAuto    := .T.
    Private lAutoErrNoFile := .T.

    // Separa o que e produto do que e complemento
    For nI := 1 To Len(aCampos)
        If Left(aCampos[nI][1], 3) == "B5_"
            aAdd(aCompl, aCampos[nI])
        Else
            aAdd(aProduto, aCampos[nI])
        EndIf
    Next nI

    // B5_COD e a chave do complemento; sem ele o MATA180 nao sabe onde gravar
    If Len(aCompl) > 0 .And. aScan(aCompl, {|x| x[1] == "B5_COD"}) == 0
        aAdd(aCompl, {"B5_COD", cCod, Nil})
    EndIf

    If nOpc == 4
        DbSelectArea("SB1")
        SB1->(DbSetOrder(1))
        If !SB1->(DbSeek(xFilial("SB1") + cCod))
            Return {.F., "Produto nao localizado para alteracao.", ""}
        EndIf
    EndIf

    // O complemento pode nao existir mesmo em produto ja cadastrado, entao a
    // opcao dele e decidida pelo proprio SB5
    If Len(aCompl) > 0
        DbSelectArea("SB5")
        SB5->(DbSetOrder(1))
        nOpcB5 := IIf(SB5->(DbSeek(xFilial("SB5") + cCod)), 4, 3)
    EndIf

    Begin Transaction

        SetFunName("MATA010")
        MSExecAuto({|x, y| MATA010(x, y)}, aProduto, nOpc)

        If lMsErroAuto
            DisarmTransaction()
            aRet := {.F., IP01Erro(aProduto, @cBruto), cBruto}
        ElseIf Len(aCompl) > 0

            SetFunName("MATA180")
            MSExecAuto({|x, y| MATA180(x, y)}, aCompl, nOpcB5)

            If lMsErroAuto
                DisarmTransaction()
                aRet := {.F., "Complemento: " + IP01Erro(aCompl, @cBruto), cBruto}
            EndIf

        EndIf

    End Transaction

    If !aRet[1]
        RollBackSX8()
    EndIf

    SetFunName(cFunOld)

Return aRet


/*/{Protheus.doc} IP01Erro
Extrai do log do ExecAuto apenas o que interessa ao usuario.

O log bruto traz uma dezena de campos de rastreio ("Id do formulario de
origem", "Valor anterior" etc.) que tornam a mensagem ilegivel. Aqui sao
aproveitados o campo com erro e a mensagem, e mensagens repetidas - o
ExecAuto costuma repetir a mesma varias vezes - aparecem uma unica vez.

@return cErro Mensagem enxuta
/*/
Static Function IP01Erro(aCampos, cBruto)

    Local aLog   := GetAutoGRLog()
    Local aMsgs  := {}
    Local cTudo  := ""
    Local cErro  := ""
    Local cMsg   := ""
    Local cCampo := ""
    Local cOrig  := ""
    Local nI     := 0
    Local nPos   := 0

    If ValType(aLog) != "A"
        aLog := {}
    EndIf

    For nI := 1 To Len(aLog)
        cTudo += " " + AllTrim(aLog[nI])
    Next nI

    cTudo := StrTran(cTudo, Chr(13), " ")
    cTudo := StrTran(cTudo, Chr(10), " ")

    // O log completo vai para o arquivo e para o console: quando a extracao
    // abaixo nao reconhece o formato, e nele que esta a resposta
    cBruto := AllTrim(Left(cTudo, IMP_MAXDET))
    ConOut("[zImpPro] " + cBruto)

    // O ExecAuto repete a mesma mensagem em varios blocos, e nem todos trazem
    // a origem. Por isso cada mensagem e guardada uma unica vez, ficando com o
    // melhor prefixo encontrado em qualquer um dos blocos.
    While "Mensagem do erro:" $ cTudo

        cMsg   := IP01Tag(cTudo, "Mensagem do erro:")
        cCampo := IP01Tag(cTudo, "Id do campo de erro:")

        // Sem campo identificado, o "Id do erro" e a unica pista da origem -
        // e o caso das recusas vindas de integracao. Ids com digitos
        // ("SFCC101") sao codigos internos e nao dizem nada ao usuario.
        If Empty(cCampo)
            cOrig := IP01Tag(cTudo, "Id do erro:")
            If !IP01TemNum(cOrig)
                cCampo := cOrig
            EndIf
        EndIf

        If !Empty(cMsg)
            nPos := aScan(aMsgs, {|x| x[1] == cMsg})
            If nPos == 0
                aAdd(aMsgs, {cMsg, cCampo})
            ElseIf Empty(aMsgs[nPos][2]) .And. !Empty(cCampo)
                aMsgs[nPos][2] := cCampo
            EndIf
        EndIf

        cTudo := SubStr(cTudo, At("Mensagem do erro:", cTudo) + 17)

    EndDo

    For nI := 1 To Len(aMsgs)
        cErro += IIf(Empty(cErro), "", " | ")
        cErro += IP01Amigo(aMsgs[nI][2], aMsgs[nI][1], aCampos)
    Next nI

    If Empty(cErro)
        // Formato inesperado: devolve o texto bruto, ainda melhor que nada
        cErro := AllTrim(Left(cTudo, 250))
    EndIf

    If Empty(cErro)
        cErro := "Erro nao identificado pelo ExecAuto."
    EndIf

Return cErro


/*/{Protheus.doc} IP01Amigo
Reescreve a recusa do ExecAuto em termos que o usuario entenda.

A mensagem crua diz o que o Protheus reclamou, mas nao o que fazer, e
identifica o campo pelo nome tecnico. Aqui entram o titulo do dicionario,
o valor que foi enviado e, para os motivos mais comuns, a acao esperada.
Motivo nao reconhecido mantem o texto original - melhor um texto tecnico
do que uma traducao que perca a informacao.

@param cCampo  Campo com erro, ou a origem (INTEGRACAO, OBRIGAT...)
@param cMsg    Mensagem do ExecAuto
@param aCampos Campos enviados, de onde sai o valor recusado
@return cRet   Mensagem para a tela
/*/
Static Function IP01Amigo(cCampo, cMsg, aCampos)

    Local cRet   := ""
    Local cTit   := ""
    Local cValor := ""
    Local cUpper := Upper(cMsg)
    Local nPos   := 0

    // Origem sem campo: tipicamente recusa de integracao
    If Empty(cCampo) .Or. !("_" $ cCampo)
        If "JA EXISTE" $ cUpper
            Return "Produto ja existe no sistema externo - recusado pela " + ;
                   IIf(Empty(cCampo), "integracao", cCampo) + ", nao pelo Protheus"
        EndIf
        Return IIf(Empty(cCampo), "", cCampo + ": ") + cMsg
    EndIf

    cTit := IP01Titulo(cCampo)
    nPos := aScan(aCampos, {|x| x[1] == cCampo})

    If nPos > 0 .And. ValType(aCampos[nPos][2]) == "C"
        cValor := AllTrim(aCampos[nPos][2])
    EndIf

    // Identificacao do campo: nome tecnico com o titulo ao lado
    cRet := cCampo + IIf(Empty(cTit), "", " (" + cTit + ")")

    Do Case
        Case "NAO FOI PREENCHIDO" $ cUpper .Or. "OBRIGAT" $ cUpper
            cRet += ": nao foi preenchido - inclua esta coluna no arquivo"

        Case "NAO CADASTRAD" $ cUpper .Or. "NAO EXISTE" $ cUpper .Or. ;
             "INEXISTENTE" $ cUpper
            cRet += IIf(Empty(cValor), "", ' = "' + cValor + '"')
            cRet += ": este valor nao esta cadastrado no sistema"

        Case "INVALID" $ cUpper
            cRet += IIf(Empty(cValor), "", ' = "' + cValor + '"')
            cRet += ": valor recusado pela validacao do campo"

        Otherwise
            cRet += IIf(Empty(cValor), "", ' = "' + cValor + '"')
            cRet += ": " + cMsg
    EndCase

Return cRet


/*/{Protheus.doc} IP01Titulo
Titulo do campo no dicionario. Usado so na montagem de mensagens de erro,
entao a consulta ao SX3 por campo nao pesa no processamento.
/*/
Static Function IP01Titulo(cCampo)

    Local cRet  := ""
    Local aArea := SX3->(GetArea())
    Local nOrd  := SX3->(IndexOrd())

    SX3->(DbSetOrder(2))    // X3_CAMPO

    If SX3->(DbSeek(PadR(cCampo, Len(SX3->X3_CAMPO))))
        cRet := AllTrim(X3Titulo())
    EndIf

    SX3->(DbSetOrder(nOrd))
    SX3->(RestArea(aArea))

Return cRet


/*/{Protheus.doc} IP01TemNum
Indica se o texto contem algum digito.
/*/
Static Function IP01TemNum(cTexto)

    Local nI := 0

    For nI := 1 To Len(cTexto)
        If IsDigit(SubStr(cTexto, nI, 1))
            Return .T.
        EndIf
    Next nI

Return .F.


/*/{Protheus.doc} IP01Tag
Devolve o conteudo entre colchetes que segue uma etiqueta do log.
Ex.: "Mensagem do erro: [texto]" -> "texto"
/*/
Static Function IP01Tag(cTexto, cTag)

    Local cRet := ""
    Local cAux := ""
    Local nPos := At(cTag, cTexto)
    Local nIni := 0
    Local nFim := 0

    If nPos == 0
        Return ""
    EndIf

    cAux := SubStr(cTexto, nPos + Len(cTag), 300)
    nIni := At("[", cAux)
    nFim := At("]", cAux)

    If nIni > 0 .And. nFim > nIni
        cRet := AllTrim(SubStr(cAux, nIni + 1, nFim - nIni - 1))
    EndIf

Return cRet


// ===========================================================================
// LEITURA DO ARQUIVO
// ===========================================================================

/*/{Protheus.doc} IP01LerArq
Le o arquivo do servidor e devolve as linhas ja tratadas.
A codificacao (UTF-8 ou ANSI) e detectada pelo conteudo.
/*/
Static Function IP01LerArq(cArq, cErro)

    Local aLin  := {}
    Local oFile
    Local cTudo := ""
    Local nI    := 0

    cErro := ""

    oFile := FWFileReader():New(cArq)

    If oFile:Open()
        While oFile:HasLine()
            cTudo += oFile:GetLine() + Chr(10)
        EndDo
        oFile:Close()
    EndIf

    // Alternativa quando o reader nao devolve o conteudo esperado
    If Empty(cTudo)
        cTudo := MemoRead(cArq)
    EndIf

    If Empty(cTudo)
        cErro := "Nao foi possivel ler o arquivo:" + CRLF + cArq
        Return aLin
    EndIf

    If SubStr(cTudo, 1, 3) == IMP_BOM
        cTudo := SubStr(cTudo, 4)
    EndIf

    If IP01EhUtf8(cTudo)
        cTudo := DecodeUTF8(cTudo)
    EndIf

    aLin := IP01Quebra(cTudo)

    For nI := Len(aLin) To 1 Step -1
        If Empty(AllTrim(aLin[nI]))
            aSize(aLin, nI - 1)
        Else
            Exit
        EndIf
    Next nI

Return aLin


/*/{Protheus.doc} IP01EhUtf8
Indica se o texto contem sequencias de acentuacao em UTF-8.
Evita pedir a codificacao ao usuario, que raramente sabe informar.
/*/
Static Function IP01EhUtf8(cTexto)

    Local nI  := 0
    Local nB1 := 0
    Local nB2 := 0
    Local nFim := Min(Len(cTexto), 20000)

    For nI := 1 To nFim - 1
        nB1 := Asc(SubStr(cTexto, nI, 1))
        If nB1 >= 194 .And. nB1 <= 195
            nB2 := Asc(SubStr(cTexto, nI + 1, 1))
            If nB2 >= 128 .And. nB2 <= 191
                Return .T.
            EndIf
        EndIf
    Next nI

Return .F.


/*/{Protheus.doc} IP01Quebra
Quebra o texto em linhas, aceitando CRLF, LF e CR.
/*/
Static Function IP01Quebra(cTexto)

    Local aRet := {}
    Local cAux := StrTran(StrTran(cTexto, Chr(13) + Chr(10), Chr(10)), Chr(13), Chr(10))
    Local nPos := At(Chr(10), cAux)

    While nPos > 0
        aAdd(aRet, SubStr(cAux, 1, nPos - 1))
        cAux := SubStr(cAux, nPos + 1)
        nPos := At(Chr(10), cAux)
    EndDo

    aAdd(aRet, cAux)

Return aRet


/*/{Protheus.doc} IP01Separ
Descobre o separador pela linha de cabecalho.
/*/
Static Function IP01Separ(cLinha)

    Local cSep := ";"

    Do Case
        Case IP01Conta(cLinha, ";")     > 0 ; cSep := ";"
        Case IP01Conta(cLinha, "|")     > 0 ; cSep := "|"
        Case IP01Conta(cLinha, IMP_TAB) > 0 ; cSep := IMP_TAB
        Case IP01Conta(cLinha, ",")     > 0 ; cSep := ","
    EndCase

Return cSep


Static Function IP01Conta(cTexto, cChar)
Return Len(cTexto) - Len(StrTran(cTexto, cChar, ""))


/*/{Protheus.doc} IP01Split
Quebra a linha em colunas respeitando o conteudo entre aspas, para que uma
descricao como "CABO 2,5MM; AZUL" nao seja dividida.
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
// MAPEAMENTO E CONVERSAO
// ===========================================================================

/*/{Protheus.doc} IP01Mapa
Monta o mapa de colunas a partir do cabecalho, validando cada nome contra o
dicionario (SX3) de SB1 e SB5.

Coluna desconhecida NAO interrompe a importacao: ela e apenas descartada e
devolvida em aIgnora, para constar do resumo. Interromper tudo por causa de
uma coluna extra na planilha tornava a rotina dificil de usar.

@param aIgnora Por referencia, recebe os nomes descartados
@param cErro   Por referencia, so preenchido em erro que impede a carga
@return aMapa  {nColuna, cCampo, cTipo, nTam, nDec}
/*/
Static Function IP01Mapa(cHeader, cSepar, aIgnora, cErro)

    Local aMapa  := {}
    Local aCols  := IP01Split(cHeader, cSepar)
    Local aDicio := IP01Dicio()
    Local cCol   := ""
    Local nI     := 0
    Local nPos   := 0

    cErro   := ""
    aIgnora := {}

    For nI := 1 To Len(aCols)

        cCol := Upper(AllTrim(aCols[nI]))

        If Empty(cCol)
            Loop
        EndIf

        nPos := aScan(aDicio, {|x| x[1] == cCol})

        If nPos == 0                                  // tenta pelo titulo
            nPos := aScan(aDicio, {|x| Upper(x[5]) == cCol})
        EndIf

        If nPos == 0 .Or. aScan(aMapa, {|x| x[2] == aDicio[nPos][1]}) > 0
            aAdd(aIgnora, cCol)
            Loop
        EndIf

        aAdd(aMapa, {nI, aDicio[nPos][1], aDicio[nPos][2], aDicio[nPos][3], aDicio[nPos][4]})

    Next nI

    If aScan(aMapa, {|x| x[2] == "B1_COD"}) == 0
        cErro := "A coluna B1_COD nao foi encontrada no cabecalho do arquivo." + CRLF + CRLF + ;
                 "A primeira linha precisa conter os nomes tecnicos dos campos, " + ;
                 "por exemplo:" + CRLF + "B1_COD;B1_DESC;B1_TIPO;B1_UM"
    EndIf

Return aMapa


/*/{Protheus.doc} IP01Dicio
Campos reais de SB1 e SB5. Descarta virtuais (nao podem ser gravados pelo
ExecAuto) e campos de filial (definidos pelo ambiente).

@return aDic {cCampo, cTipo, nTam, nDec, cTitulo}
/*/
Static Function IP01Dicio()

    Local aDic  := {}
    Local aArqs := {"SB1", "SB5"}
    Local aArea := SX3->(GetArea())
    Local nOrd  := SX3->(IndexOrd())
    Local nI    := 0
    Local cCpo  := ""

    SX3->(DbSetOrder(1))

    For nI := 1 To Len(aArqs)
        If SX3->(DbSeek(aArqs[nI]))
            While !SX3->(Eof()) .And. AllTrim(SX3->X3_ARQUIVO) == aArqs[nI]
                cCpo := AllTrim(SX3->X3_CAMPO)
                If AllTrim(SX3->X3_CONTEXT) != "V" .And. Right(cCpo, 7) != "_FILIAL"
                    aAdd(aDic, {cCpo, AllTrim(SX3->X3_TIPO), SX3->X3_TAMANHO, ;
                                SX3->X3_DECIMAL, AllTrim(X3Titulo())})
                EndIf
                SX3->(DbSkip())
            EndDo
        EndIf
    Next nI

    SX3->(DbSetOrder(nOrd))
    SX3->(RestArea(aArea))

Return aDic


/*/{Protheus.doc} IP01Reg
Monta o array de campos do ExecAuto a partir de uma linha do arquivo.

Coluna vazia e omitida de proposito: na inclusao a rotina automatica aplica
o padrao do dicionario e na alteracao preserva o conteudo atual.
/*/
Static Function IP01Reg(cLinha, cSepar, aMapa, aCopia, cErro)

    Local aCpo   := {}
    Local aCols  := IP01Split(cLinha, cSepar)
    Local aFixos := IP01Fixos()
    Local cValor := ""
    Local cAux   := ""
    Local xValor
    Local nI     := 0
    Local nCol   := 0
    Local nPos   := 0

    cErro := ""

    For nI := 1 To Len(aMapa)

        nCol := aMapa[nI][1]

        If nCol > Len(aCols)
            Loop
        EndIf

        cValor := AllTrim(aCols[nCol])

        If Empty(cValor)
            Loop
        EndIf

        xValor := IP01Conv(cValor, aMapa[nI][3], aMapa[nI][4], aMapa[nI][5], ;
                           aMapa[nI][2], @cErro)

        If !Empty(cErro)
            Return aCpo
        EndIf

        aAdd(aCpo, {aMapa[nI][2], xValor, Nil})

    Next nI

    // Campos derivados de outro campo - o arquivo tem prioridade
    For nI := 1 To Len(aCopia)

        If aScan(aCpo, {|x| x[1] == aCopia[nI][1]}) > 0
            Loop
        EndIf

        nPos := aScan(aCpo, {|x| x[1] == aCopia[nI][2]})

        If nPos > 0 .And. ValType(aCpo[nPos][2]) == "C"
            cAux := AllTrim(aCpo[nPos][2])
            If Len(cAux) > aCopia[nI][3]
                cAux := Left(cAux, aCopia[nI][3])
            EndIf
            aAdd(aCpo, {aCopia[nI][1], cAux, Nil})
        EndIf

    Next nI

    For nI := 1 To Len(aFixos)
        If aScan(aCpo, {|x| x[1] == aFixos[nI][1]}) == 0
            aAdd(aCpo, {aFixos[nI][1], aFixos[nI][2], Nil})
        EndIf
    Next nI

Return aCpo


/*/{Protheus.doc} IP01PrepCop
Resolve o tamanho de cada campo de destino uma unica vez, antes do laco de
linhas - consultar o dicionario a cada produto pesaria em cargas grandes.

Campos que nao existem no dicionario sao descartados aqui, para nao chegar
ao ExecAuto.

@return aRet Array de {cDestino, cOrigem, nTamanho}
/*/
Static Function IP01PrepCop()

    Local aCop := IP01Copia()
    Local aRet := {}
    Local aTam := {}
    Local nI   := 0

    For nI := 1 To Len(aCop)
        aTam := TamSX3(aCop[nI][1])
        If ValType(aTam) == "A" .And. Len(aTam) > 0 .And. aTam[1] > 0
            aAdd(aRet, {aCop[nI][1], aCop[nI][2], aTam[1]})
        EndIf
    Next nI

Return aRet


/*/{Protheus.doc} IP01Conv
Converte o texto lido para o tipo do campo no dicionario.
/*/
Static Function IP01Conv(cValor, cTipo, nTam, nDec, cCampo, cErro)

    Local xRet := Nil

    cErro := ""

    Do Case
        Case cTipo == "C" .Or. cTipo == "M"
            If cTipo == "C" .And. Len(cValor) > nTam
                cErro := cCampo + ": o conteudo tem " + cValToChar(Len(cValor)) + ;
                         " caracteres e o campo aceita " + cValToChar(nTam) + "."
                Return Nil
            EndIf
            xRet := cValor

        Case cTipo == "N"
            xRet := IP01Num(cValor, @cErro)
            If !Empty(cErro)
                cErro := cCampo + ": " + cErro
                Return Nil
            EndIf
            xRet := Round(xRet, nDec)

        Case cTipo == "D"
            xRet := IP01Data(cValor, @cErro)
            If !Empty(cErro)
                cErro := cCampo + ": " + cErro
                Return Nil
            EndIf

        Case cTipo == "L"
            xRet := (Upper(cValor) $ "1/S/SIM/T/.T./TRUE/V")

        Otherwise
            cErro := cCampo + ": tipo de campo '" + cTipo + "' nao suportado."
            Return Nil
    EndCase

Return xRet


/*/{Protheus.doc} IP01Num
Converte texto em numero nos formatos brasileiro (1.234,56) e americano.
/*/
Static Function IP01Num(cValor, cErro)

    Local cLimpo := ""
    Local cChar  := ""
    Local nI     := 0
    Local nPto   := 0
    Local nVir   := 0

    cErro := ""

    For nI := 1 To Len(cValor)
        cChar := SubStr(cValor, nI, 1)
        If cChar $ "0123456789.,-+"
            cLimpo += cChar
        ElseIf !(cChar $ " R$%")
            cErro := "'" + cValor + "' nao e um numero valido."
            Return 0
        EndIf
    Next nI

    If Empty(cLimpo)
        Return 0
    EndIf

    nPto := RAt(".", cLimpo)
    nVir := RAt(",", cLimpo)

    Do Case
        Case nPto > 0 .And. nVir > 0
            If nVir > nPto
                cLimpo := StrTran(StrTran(cLimpo, ".", ""), ",", ".")
            Else
                cLimpo := StrTran(cLimpo, ",", "")
            EndIf
        Case nVir > 0
            cLimpo := StrTran(cLimpo, ",", ".")
        Case nPto > 0 .And. IP01Conta(cLimpo, ".") > 1
            cLimpo := StrTran(cLimpo, ".", "")
    EndCase

Return Val(cLimpo)


/*/{Protheus.doc} IP01Data
Converte texto em data (DD/MM/AAAA, DD-MM-AAAA, AAAAMMDD, AAAA-MM-DD).
/*/
Static Function IP01Data(cValor, cErro)

    Local cAux := StrTran(StrTran(cValor, "-", "/"), ".", "/")
    Local dRet := CToD("")

    cErro := ""

    Do Case
        Case Len(cAux) == 8 .And. !("/" $ cAux)
            dRet := SToD(cAux)
        Case Len(cAux) == 10 .And. SubStr(cAux, 5, 1) == "/"
            dRet := SToD(StrTran(cAux, "/", ""))
        Case "/" $ cAux
            dRet := CToD(cAux)
    EndCase

    If Empty(dRet)
        cErro := "'" + cValor + "' nao e uma data valida."
    EndIf

Return dRet


/*/{Protheus.doc} IP01RecDel
Devolve o R_E_C_N_O_ quando o codigo pertence a um produto excluido, ou 0.
/*/
Static Function IP01RecDel(cCod)

    Local nRec    := 0
    Local aArea   := SB1->(GetArea())
    Local lDelAnt := Set(_SET_DELETED)

    Set(_SET_DELETED, .F.)
    SB1->(DbSetOrder(1))

    If SB1->(DbSeek(xFilial("SB1") + cCod)) .And. SB1->(Deleted())
        nRec := SB1->(Recno())
    EndIf

    Set(_SET_DELETED, lDelAnt)
    SB1->(RestArea(aArea))

Return nRec


// ===========================================================================
// RESULTADO
// ===========================================================================

/*/{Protheus.doc} IP01Result
Mostra o resultado: resumo e, quando ha rejeicoes, a lista com o motivo de
cada linha. O usuario final nao tem acesso a pasta de log no servidor, entao
tudo que ele precisa para corrigir o arquivo esta nesta tela.
/*/
Static Function IP01Result(aRes, lSimula)

    Local oDlg, oMemo, oBrw
    Local aRej   := aRes[RES_REJEIT]
    Local cArqLog := ""
    Local cTexto := ""

    // Erro que impediu a leitura: mensagem direta, sem tela de resultado
    If !Empty(aRes[RES_FATAL])
        MsgStop(aRes[RES_FATAL], "Nao foi possivel importar")
        Return Nil
    EndIf

    cArqLog := IP01Log(aRes, lSimula)

    cTexto := IIf(lSimula, "SIMULACAO - nada foi gravado", "IMPORTACAO CONCLUIDA") + CRLF + CRLF
    cTexto += "Produtos no arquivo : " + cValToChar(aRes[RES_LIDAS])   + CRLF
    cTexto += "Incluidos ..........: " + cValToChar(aRes[RES_INCLUIU]) + CRLF
    cTexto += "Alterados ..........: " + cValToChar(aRes[RES_ALTEROU]) + CRLF
    cTexto += "Ja existiam ........: " + cValToChar(aRes[RES_IGNOROU]) + CRLF
    cTexto += "Com problema .......: " + cValToChar(aRes[RES_ERROS])   + CRLF

    If !Empty(aRes[RES_DESCARTA])
        cTexto += CRLF + "Colunas desconhecidas, ignoradas na importacao:" + CRLF + ;
                  aRes[RES_DESCARTA] + CRLF
    EndIf

    If !Empty(cArqLog)
        cTexto += CRLF + "Log: " + cArqLog
    EndIf

    DEFINE MSDIALOG oDlg TITLE "Resultado da Importacao" FROM 0, 0 TO 400, 760 PIXEL

    @ 005, 005 GET oMemo VAR cTexto MEMO SIZE 365, 070 PIXEL OF oDlg
    oMemo:lReadOnly := .T.

    If Len(aRej) == 0
        @ 085, 005 SAY "Nenhum problema encontrado." SIZE 300, 10 PIXEL OF oDlg
    Else
        @ 082, 005 SAY "Linhas com problema - corrija no arquivo e importe novamente:" ;
                   SIZE 350, 09 PIXEL OF oDlg

        @ 093, 005 LISTBOX oBrw FIELDS HEADER "Linha", "Produto", "O que aconteceu" ;
                   SIZE 365, 080 PIXEL OF oDlg
        oBrw:SetArray(aRej)
        oBrw:bLine := {|| {cValToChar(aRej[oBrw:nAt][REJ_LINHA]) , ;
                           aRej[oBrw:nAt][REJ_PRODUTO]           , ;
                           aRej[oBrw:nAt][REJ_MOTIVO]            } }
    EndIf

    TButton():New(182, 300, "Fechar", oDlg, {|| oDlg:End() }, ;
                  070, 014, , , .F., .T., .F., , .F., , , .F.)

    ACTIVATE MSDIALOG oDlg CENTERED

Return Nil


/*/{Protheus.doc} IP01Log
Grava o log no servidor e copia para a maquina do usuario.

@return cArq Caminho do log, ou "" quando nao foi possivel gravar
/*/
Static Function IP01Log(aRes, lSimula)

    Local aRej := aRes[RES_REJEIT]
    Local cArq := ""
    Local nHdl := 0
    Local nI   := 0

    IP01MkDir(IMP_DIRLOG)

    cArq := IMP_DIRLOG + "zImpPro_" + DToS(Date()) + "_" + StrTran(Time(), ":", "") + ".log"
    nHdl := FCreate(cArq)

    If nHdl == -1
        Return ""
    EndIf

    FWrite(nHdl, "Importacao de Produtos - " + DToC(Date()) + " " + Time() + CRLF)
    FWrite(nHdl, "Arquivo .: " + aRes[RES_ARQUIVO] + CRLF)
    FWrite(nHdl, "Usuario .: " + AllTrim(cUserName) + CRLF)
    FWrite(nHdl, "Modo ....: " + IIf(lSimula, "SIMULACAO", "GRAVACAO") + CRLF)
    FWrite(nHdl, "Colunas .: " + aRes[RES_COLUNAS] + CRLF)

    If !Empty(aRes[RES_DESCARTA])
        FWrite(nHdl, "Ignoradas: " + aRes[RES_DESCARTA] + CRLF)
    EndIf

    FWrite(nHdl, Replicate("-", 90) + CRLF)
    FWrite(nHdl, "Produtos no arquivo: " + cValToChar(aRes[RES_LIDAS])   + CRLF)
    FWrite(nHdl, "Incluidos .........: " + cValToChar(aRes[RES_INCLUIU]) + CRLF)
    FWrite(nHdl, "Alterados .........: " + cValToChar(aRes[RES_ALTEROU]) + CRLF)
    FWrite(nHdl, "Ja existiam .......: " + cValToChar(aRes[RES_IGNOROU]) + CRLF)
    FWrite(nHdl, "Com problema ......: " + cValToChar(aRes[RES_ERROS])   + CRLF)

    If Len(aRej) > 0
        FWrite(nHdl, Replicate("-", 90) + CRLF)
        For nI := 1 To Len(aRej)
            FWrite(nHdl, "Linha " + StrZero(aRej[nI][REJ_LINHA], 6) + " " + ;
                         PadR(aRej[nI][REJ_PRODUTO], 20) + " " + ;
                         aRej[nI][REJ_MOTIVO] + CRLF)

            // Log bruto do ExecAuto: e aqui que esta a resposta quando a
            // mensagem resumida nao explica a recusa
            If !Empty(aRej[nI][REJ_DETALHE])
                FWrite(nHdl, "       ExecAuto: " + aRej[nI][REJ_DETALHE] + CRLF)
            EndIf
        Next nI
    EndIf

    FClose(nHdl)

    // Copia para a maquina do usuario; se a pasta nao existir, segue sem erro
    If !Empty(IMP_DIREST)
        CpyS2T(cArq, IMP_DIREST, .T.)
    EndIf

Return cArq


// ===========================================================================
// AUXILIARES
// ===========================================================================

Static Function IP01Lista(aMapa)

    Local cRet := ""
    Local nI   := 0

    For nI := 1 To Len(aMapa)
        cRet += aMapa[nI][2] + IIf(nI < Len(aMapa), ", ", "")
    Next nI

Return cRet


Static Function IP01Junta(aLista)

    Local cRet := ""
    Local nI   := 0

    For nI := 1 To Len(aLista)
        cRet += aLista[nI] + IIf(nI < Len(aLista), ", ", "")
    Next nI

Return cRet


Static Function IP01MkDir(cDir)

    Local cAux := AllTrim(cDir)

    If Right(cAux, 1) != "\"
        cAux += "\"
    EndIf

    If !ExistDir(cAux)
        MakeDir(cAux)
    EndIf

Return Nil


Static Function IP01NmArq(cCaminho)

    Local cRet := StrTran(AllTrim(cCaminho), "/", "\")
    Local nPos := RAt("\", cRet)

    If nPos > 0
        cRet := SubStr(cRet, nPos + 1)
    EndIf

Return cRet
