# Manual — zImpPro (Importação de Produtos via ExecAuto)

Versão 1.00 · Protheus 12.1.2410 · SmartClient HTML (navegador)

---

## 1. Instalação

1. Compile `src/IMPPRD01.prw` no RPO do ambiente.
2. Cadastre a rotina no menu (SIGAMDI):
   - **Programa:** `U_zImpPro`
   - **Tipo:** Função Protheus
   - **Módulo:** SIGAEST (Estoque/Custos) ou o de sua preferência
3. Diretórios utilizados no *rootpath* do Protheus (criados automaticamente):

```
\imp_produtos\          arquivos a importar
\imp_produtos\log\      logs e arquivos de rejeitados
```

---

## 2. Por que ExecAuto

A gravação nunca é feita por `RecLock`/`Replace`. Todo registro passa por:

```advpl
MSExecAuto({|x, y| MATA010(x, y)}, aCampos, nOpcAuto)
```

Com isso são executados: validações `X3_VALID`, gatilhos (SX7), consistências
internas do MATA010, pontos de entrada (`MT010TOK`, `MT010OK` etc.) e a gravação
do complemento **SB5** — exatamente como se o produto tivesse sido digitado na tela.

O erro é capturado por `GetAutoGRLog()` em vez de `MostraErro()`, o que evita
que a importação em lote fique travada esperando alguém clicar em "OK".

---

## 3. Tela da rotina

| Campo | Descrição |
|---|---|
| **Arquivo** | Caminho do arquivo. O botão `...` abre o seletor da máquina local. |
| **Separador** | `;` · `\|` · TAB · `,` · Detectar automaticamente |
| **Codificação** | `1` Arquivo UTF-8 (converte) · `2` ANSI/Excel (não converte) · `3` Ambiente UTF-8 |
| **Primeira linha contém os nomes dos campos** | Marcado = mapeamento dinâmico pelo cabeçalho (padrão) |
| **Atualizar produtos já cadastrados** | Desmarcado = produto existente é apenas ignorado |
| **Somente simular** | Valida o arquivo inteiro **sem gravar nada** |
| **Log (servidor)** | Onde o log é gravado **no AppServer** (`FCreate` sempre grava no servidor) |
| **Copiar p/ (estação)** | Pasta na **sua máquina** para onde o log é copiado ao final. Em branco = não copia |

Botões: **Gerar arquivo modelo** (cria `\imp_produtos\MODELO_PRODUTOS.csv` a partir
do layout do fonte), **Importar** e **Sair**.

### Como o arquivo chega ao servidor

O botão `...` abre `cGetFile()` com `GETF_LOCALHARD`, que abre o seletor nativo
na **máquina de quem está usando o sistema** — nunca o disco do servidor. O que
acontece depois depende do SmartClient:

| SmartClient | Comportamento |
|---|---|
| **HTML (navegador)** | O framework transfere o arquivo para uma área temporária do AppServer e devolve um caminho já legível no servidor. Nada a fazer. |
| **Desktop (exe)** | O caminho devolvido é da estação; a rotina traz o arquivo para `\imp_produtos\` com `CpyT2S()`. |

A rotina detecta o caso testando `File()` sobre o caminho devolvido: se o
AppServer já enxerga o arquivo, usa direto; senão, transfere. A leitura e o
processamento em `IP01Proc()` ocorrem sempre no servidor.

> Não é usado `__CopyFile()`: funções com prefixo `__` são de uso interno e o
> compilador AdvPL já emite o aviso `W9910`, que virará erro em versões futuras.
> `CpyT2S()` é a função documentada para transferir da estação para o servidor —
> note que o 2º parâmetro dela é o **diretório** de destino, não o nome do arquivo.

---

## 4. Layout do arquivo

### 4.1 Modo recomendado — com cabeçalho

A primeira linha traz os **nomes técnicos dos campos**, em qualquer ordem:

```
B1_COD;B1_DESC;B1_TIPO;B1_UM;B1_SEGUM;B1_LOCPAD;B1_GRUPO;B1_POSIPI;B1_ORIGEM;B1_PRV1;B1_CUSTD;B1_PICM;B1_IPI;B1_CONTA
PA000001;PARAFUSO SEXTAVADO 1/2 X 2;MP;PC;PC;01;0001;73181500;0;12,50;8,30;18,00;5,00;11010001
PA000002;"CABO FLEXIVEL 2,5MM; AZUL";MP;MT;MT;01;0001;85444200;0;3,75;2,10;18,00;0,00;11010001
```

**Vantagem:** para importar um campo novo basta acrescentar a coluna no arquivo —
sem alterar nem recompilar o fonte.

Regras:

- Aceita o **título do dicionário** no lugar do nome técnico (`Descricao` ≡ `B1_DESC`).
- Aceita campos de **SB1** e de **SB5** (complemento) no mesmo arquivo.
- `B1_COD` é obrigatório.
- Colunas listadas em `IP01Ignora()` são desprezadas (`OBS`, `IGNORAR`, `ERRO`, `MOTIVO`…).
- Campo inexistente no SX3 aborta a importação com mensagem indicando a coluna.
- Coluna repetida no cabeçalho é rejeitada.
- **Campos virtuais** (`X3_CONTEXT = "V"`) não são aceitos: não existem fisicamente
  na tabela e não podem ser gravados pelo ExecAuto.
- **Campos de controle** (`B1_FILIAL`, `B5_FILIAL`, `D_E_L_E_T_`, `R_E_C_N_O_`) são
  bloqueados — a filial é definida pelo ambiente (`xFilial`).

### 4.2 Modo layout fixo — sem cabeçalho

Desmarque a opção de cabeçalho. A ordem das colunas passa a ser a definida em
`IP01Layout()`, no início do fonte:

```advpl
Static Function IP01Layout()
    Local aLay := {}
    //         Campo         Descricao
    aAdd(aLay, {"B1_COD"   , "Codigo do produto"   })
    aAdd(aLay, {"B1_DESC"  , "Descricao"           })
    aAdd(aLay, {"B1_TIPO"  , "Tipo (SX5 tabela 02)"})
    // ...
Return aLay
```

### 4.3 Conversão de conteúdo

| Tipo (X3_TIPO) | Formatos aceitos |
|---|---|
| `C` Caractere | Texto; erro se exceder `X3_TAMANHO` |
| `N` Numérico | `1234.56`, `1.234,56`, `1234,56`; ignora `R$`, `%` e espaços; arredonda por `X3_DECIMAL` |
| `D` Data | `DD/MM/AAAA`, `DD-MM-AAAA`, `AAAAMMDD`, `AAAA-MM-DD` |
| `L` Lógico | `1`, `S`, `SIM`, `T`, `.T.`, `V`, `VERDADEIRO` = verdadeiro |
| `M` Memo | Texto, sem validação de tamanho |

**Coluna vazia é omitida do ExecAuto**, de propósito: na inclusão o MATA010 aplica
o padrão do dicionário (`X3_RELACAO`) e na alteração o conteúdo atual é preservado.

O parser respeita aspas duplas, então `"CABO 2,5MM; AZUL"` permanece em uma única
coluna mesmo com o `;` no meio. Aspas duplicadas (`""`) viram uma aspa literal.

---

## 5. Inclusão × Alteração

A decisão é automática:

| Situação | Ação |
|---|---|
| `B1_COD` não existe no SB1 | Inclusão — `MATA010` com `nOpc = 3` |
| `B1_COD` existe e "Atualizar" **marcado** | Alteração — `MATA010` com `nOpc = 4` (SB1 posicionado antes) |
| `B1_COD` existe e "Atualizar" **desmarcado** | Ignorado e registrado no log |

Códigos duplicados **dentro do próprio arquivo** são rejeitados — o segundo seria
processado como alteração do primeiro, mascarando um erro de origem.

---

## 6. Tratamento de erros

- Cada linha roda dentro de `Begin Transaction ... End Transaction`. Havendo
  `lMsErroAuto`, é feito `DisarmTransaction()` + `RollBackSX8()` e o processamento
  **segue para a próxima linha**.
- O texto do erro vem de `GetAutoGRLog()`, consolidado em uma linha.
- Ao final são gerados:

```
\imp_produtos\log\zImpPro_AAAAMMDD_HHMMSS.log        log completo
\imp_produtos\log\REJEITADOS_AAAAMMDD_HHMMSS.csv     linhas rejeitadas + motivo
```

O CSV de rejeitados traz `LINHA;PRODUTO;MOTIVO;CONTEUDO_ORIGINAL`, permitindo
corrigir e reimportar somente o que falhou.

### Tela de resultado

Ao final a rotina abre uma janela com o resumo e duas abas:

| Aba | Conteúdo |
|---|---|
| **Rejeitados (N)** | Browse navegável com linha, produto e motivo de cada rejeição |
| **Log completo** | Log detalhado em texto (limitado a 500 linhas em tela) |

O browse existe porque **o usuário final normalmente não tem acesso à pasta de
log no servidor**. Com ele, dá para identificar e corrigir os erros direto na
tela, sem depender de arquivo nenhum.

O botão **"Salvar rejeitados na minha maquina"** permite escolher uma pasta na
estação e levar o CSV até lá (`CpyS2T`) — é conveniência, não pré-requisito.

### Onde os logs ficam: servidor × sua máquina

**`FCreate()`/`FWrite()` sempre gravam no AppServer, nunca na estação.** Um caminho
como `C:\Erros Protheus` digitado no campo *Log (servidor)* aponta para o disco C
**do servidor** — só coincide com a sua máquina se o AppServer rodar localmente.

Por isso existem dois campos separados:

| Campo | Onde grava | Função usada |
|---|---|---|
| **Log (servidor)** | AppServer, dentro do *rootpath* | `FCreate` / `FWrite` |
| **Copiar p/ (estação)** | Sua máquina | `CpyS2T()` |

Ao final da importação o log e o CSV de rejeitados são copiados para a pasta
informada no segundo campo (padrão `C:\Erros Protheus`, definido na constante
`IMP_DIRESTA`). O resumo em tela informa se a cópia foi concluída.

Dois detalhes importantes:

- **A pasta precisa existir na sua máquina.** `MakeDir()` criaria no servidor,
  não na estação — então crie-a manualmente uma vez.
- **No SmartClient HTML (navegador)** a transferência é tratada como download
  pelo browser, que pode salvar na pasta de *Downloads* em vez do caminho
  informado. No SmartClient desktop o caminho é respeitado.

**Sugestão de uso:** rode primeiro com **"Somente simular"** marcado. Isso valida
layout, dicionário, tipos, tamanhos e duplicidades sem gravar nada.

---

## 7. Personalização

Três funções concentram a manutenção, todas no início do fonte:

```advpl
IP01Layout()   // ordem das colunas no modo sem cabeçalho
IP01Fixos()    // valores fixos aplicados a todos os registros
IP01Ignora()   // colunas do arquivo que devem ser desprezadas
```

`IP01Fixos()` só é aplicado quando a coluna **não veio preenchida** no arquivo —
o conteúdo do arquivo sempre tem prioridade:

```advpl
Static Function IP01Fixos()
    Local aFix := {}
    aAdd(aFix, {"B1_MSBLQL", "2"})   // produto liberado
    // aAdd(aFix, {"B1_LOCPAD", "01"})
    // aAdd(aFix, {"B1_ORIGEM", "0" })
Return aFix
```

---

## 8. Consultas SQL de apoio (SQL Server)

Substitua `XXX` pelo código da empresa das tabelas.

**Conferir o que foi importado hoje:**

```sql
SELECT B1_COD, B1_DESC, B1_TIPO, B1_UM, B1_GRUPO, B1_LOCPAD, B1_PRV1, D_E_L_E_T_
  FROM SB1XXX
 WHERE D_E_L_E_T_ = ''
   AND B1_COD LIKE 'PA%'
 ORDER BY B1_COD;
```

**Quais códigos do arquivo já existem na base** (carregue o arquivo em uma tabela
temporária `#IMP` antes de importar):

```sql
SELECT i.B1_COD,
       CASE WHEN b.B1_COD IS NULL THEN 'INCLUSAO' ELSE 'ALTERACAO' END AS ACAO
  FROM #IMP i
  LEFT JOIN SB1XXX b
         ON b.B1_COD    = i.B1_COD
        AND b.B1_FILIAL = '  '        -- ajuste conforme o compartilhamento do SB1
        AND b.D_E_L_E_T_ = ''
 ORDER BY 2, 1;
```

**Validar domínios antes da carga** (evita rejeição em massa no ExecAuto):

```sql
-- Tipos de produto validos (SX5 tabela 02)
SELECT X5_CHAVE, X5_DESCRI FROM SX5XXX
 WHERE X5_TABELA = '02' AND D_E_L_E_T_ = '' ORDER BY X5_CHAVE;

-- Unidades de medida
SELECT AH_UNIMED, AH_DESCPO FROM SAHXXX
 WHERE D_E_L_E_T_ = '' ORDER BY AH_UNIMED;

-- Grupos de produto
SELECT BM_GRUPO, BM_DESC FROM SBMXXX
 WHERE D_E_L_E_T_ = '' ORDER BY BM_GRUPO;

-- Armazens
SELECT NNR_CODIGO, NNR_DESCRI FROM NNRXXX
 WHERE D_E_L_E_T_ = '' ORDER BY NNR_CODIGO;
```

**Campos disponíveis para montar o cabeçalho do arquivo:**

```sql
SELECT X3_ARQUIVO, X3_CAMPO, X3_TITULO, X3_TIPO, X3_TAMANHO, X3_DECIMAL, X3_OBRIGAT
  FROM SX3XXX
 WHERE X3_ARQUIVO IN ('SB1','SB5')
   AND D_E_L_E_T_  = ''
   AND X3_CONTEXT <> 'V'              -- exclui virtuais (nao aceitos na carga)
   AND X3_CAMPO NOT LIKE '%[_]FILIAL' -- exclui campo de controle
 ORDER BY X3_ARQUIVO, X3_ORDEM;
```

Os campos obrigatórios (`X3_OBRIGAT = 'S'`) precisam vir no arquivo ou ter valor
padrão, senão o ExecAuto rejeita o registro.

> **Na prática:** além dos campos "óbvios", duas exigências costumam aparecer só
> na primeira carga real — **`B1_SEGUM`** (segunda unidade de medida) e
> **`B1_CONTA`** (conta contábil). Ambos já constam do layout padrão. Se ao
> preencher `B1_SEGUM` a base passar a exigir `B1_CONV` e `B1_TIPCONV` (fator e
> tipo de conversão), acrescente-os também.

**Produtos sem complemento SB5** (conferência pós-carga):

```sql
SELECT b.B1_COD, b.B1_DESC
  FROM SB1XXX b
  LEFT JOIN SB5XXX c
         ON c.B5_FILIAL = b.B1_FILIAL
        AND c.B5_COD    = b.B1_COD
        AND c.D_E_L_E_T_ = ''
 WHERE b.D_E_L_E_T_ = ''
   AND c.B5_COD IS NULL;
```

---

## 9. Rejeições mais comuns

| Mensagem | Causa provável |
|---|---|
| `Coluna N (XXX) nao corresponde a nenhum campo real` | Nome errado no cabeçalho, campo customizado ausente no SX3, ou campo virtual |
| `campo de controle nao pode ser importado` | Coluna de filial ou de controle no arquivo — remova-a |
| `conteudo com N caracteres excede o tamanho do dicionario` | Texto maior que `X3_TAMANHO` — trate na origem |
| `valor numerico invalido` | Caractere não numérico na coluna (verifique separador e aspas) |
| `Campo B1_COD nao informado` | Coluna do código vazia na linha |
| `Codigo XXX duplicado dentro do arquivo` | Mesmo produto repetido no arquivo |
| Erros vindos do `GetAutoGRLog()` | Validação do próprio MATA010: tipo, UM, grupo, NCM, conta contábil, TES etc. |

Acentuação saindo errada no log é sintoma de codificação: alterne a opção
**Codificação** entre `1` (UTF-8) e `2` (ANSI/Excel).

---

## 10. Estrutura do fonte

| Bloco | Funções |
|---|---|
| Entrada | `U_zImpPro` (ponto de entrada do menu) |
| Manutenção | `IP01Layout` · `IP01Fixos` · `IP01Ignora` |
| Interface | `IP01Tela` · `IP01Busca` · `IP01Inicia` · `IP01VerLog` |
| Processamento | `IP01Proc` · `IP01Exec` · `IP01GetErr` |
| Arquivo | `IP01LerArq` · `IP01Codif` · `IP01Separ` · `IP01Split` · `IP01Conta` |
| Layout | `IP01Mapa` · `IP01MapFix` · `IP01Reg` · `IP01Conv` · `IP01Num` · `IP01Data` |
| Dicionário | `IP01Dicio` · `IP01LstCpo` · `IP01CntTab` |
| Saída | `IP01GrvLog` · `IP01GrvRej` · `IP01Modelo` · `IP01MkDir` · `IP01NmArq` |
