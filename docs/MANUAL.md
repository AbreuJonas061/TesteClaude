# Manual — zImpPro (Importação de Produtos via ExecAuto)

Versão 2.00 · Protheus 12.1.2410 · SmartClient HTML

---

## 1. Instalação

1. Compile `src/IMPPRD01.prw` no RPO.
2. Cadastre no menu (SIGAMDI): **Programa** `U_zImpPro`, **Tipo** `Função Protheus`.

A pasta `\imp_produtos\log\` é criada automaticamente no *rootpath*.

---

## 2. Uso

A tela tem um campo e duas opções:

| Item | Para que serve |
|---|---|
| **Arquivo** + botão `...` | Escolhe o arquivo na máquina do usuário |
| **Somente simular** | Confere o arquivo inteiro **sem gravar** (marcado por padrão) |
| **Atualizar produtos que já existem** | Desmarcado, produto existente é apenas contado |

Fluxo recomendado: simular → corrigir o que a tela apontar → rodar sem simular.

Separador (`;`, `|`, TAB, `,`) e codificação (UTF-8 ou ANSI) são detectados pelo
conteúdo — o usuário não precisa saber informar.

---

## 3. O arquivo

Primeira linha com os **nomes técnicos dos campos**, em qualquer ordem:

```
B1_COD;B1_DESC;B1_TIPO;B1_UM;B1_SEGUM;B1_LOCPAD;B1_GRUPO;B1_PRV1;B1_CONTA;B5_CEME
PA000001;PARAFUSO SEXTAVADO;MP;PC;PC;01;0001;12,50;11010001;9092026
```

### Complemento do produto (SB5)

Os campos `B5_*` vão **no mesmo arquivo e no mesmo `MSExecAuto`** dos `B1_*`.
O `MATA010` grava SB1 e SB5 numa única chamada — **não existe (nem é preciso)
uma rotina automática separada para o SB5**.

Se o cadastro na tela exige `B5_CEME`, acrescente a coluna:

```
...;B1_CONTA;B5_CEME
...;11010001;9092026
```

Para ver os campos de complemento disponíveis:

```sql
SELECT X3_CAMPO, X3_TITULO, X3_TIPO, X3_TAMANHO, X3_OBRIGAT
  FROM SX3XXX
 WHERE X3_ARQUIVO = 'SB5' AND D_E_L_E_T_ = '' AND X3_CONTEXT <> 'V'
 ORDER BY X3_ORDEM;
```

Regras:

- Aceita campos de **SB1** e **SB5**, e o título do dicionário no lugar do nome
  técnico (`Descricao` ≡ `B1_DESC`).
- **`B1_COD` é obrigatório** — sem ele a importação não roda.
- **Coluna desconhecida é ignorada**, não trava a importação. As ignoradas
  aparecem no resumo, para você conferir se não esqueceu nada.
- Campos **virtuais** (`X3_CONTEXT = "V"`) e de **filial** não são aceitos.
- **Coluna vazia é omitida** de propósito: na inclusão o MATA010 aplica o padrão
  do dicionário; na alteração preserva o conteúdo atual.
- Descrição com o separador dentro funciona se estiver entre aspas:
  `"CABO 2,5MM; AZUL"`.

### Conversão por tipo

| Tipo | Aceita |
|---|---|
| `C` / `M` | Texto (erro se exceder `X3_TAMANHO`) |
| `N` | `1234.56`, `1.234,56`, `1234,56`; ignora `R$`, `%` |
| `D` | `DD/MM/AAAA`, `DD-MM-AAAA`, `AAAAMMDD`, `AAAA-MM-DD` |
| `L` | `1`, `S`, `SIM`, `T`, `V` = verdadeiro |

---

## 4. Campos obrigatórios

Quem define é o dicionário da sua base. Para descobrir a lista completa:

```sql
SELECT X3_CAMPO, X3_TITULO, X3_TIPO, X3_TAMANHO, X3_RELACAO
  FROM SX3XXX
 WHERE X3_ARQUIVO  = 'SB1'
   AND D_E_L_E_T_  = ''
   AND X3_OBRIGAT  = 'S'
   AND X3_CONTEXT <> 'V'
 ORDER BY X3_ORDEM;
```

Todo campo dessa lista precisa estar no arquivo, ter valor em `X3_RELACAO`, ou
entrar no `IP01Fixos()`.

> **`B1_SEGUM`** e **`B1_CONTA`** costumam ser obrigatórios e são a causa mais
> comum de rejeição em massa na primeira carga.

Os valores também precisam existir cadastrados:

```sql
SELECT X5_CHAVE, X5_DESCRI FROM SX5XXX WHERE X5_TABELA='02' AND D_E_L_E_T_='';  -- B1_TIPO
SELECT AH_UNIMED FROM SAHXXX WHERE D_E_L_E_T_='';                               -- B1_UM
SELECT BM_GRUPO  FROM SBMXXX WHERE D_E_L_E_T_='';                               -- B1_GRUPO
SELECT NNR_CODIGO FROM NNRXXX WHERE D_E_L_E_T_='';                              -- B1_LOCPAD
```

⚠️ No Excel, formate as colunas de código como **Texto** antes de salvar — senão
`01` vira `1` e o Protheus rejeita.

---

## 5. Inclusão × Alteração

| Situação | Ação |
|---|---|
| Código não existe | Inclusão (`MATA010`, `nOpc = 3`) |
| Existe e "Atualizar" marcado | Alteração (`nOpc = 4`) |
| Existe e "Atualizar" desmarcado | Contado como "já existia" |
| Código de produto **excluído** | Rejeitado com o número do registro |

O último caso merece atenção: a exclusão no Protheus é lógica, então o produto
some das consultas mas **a chave continua ocupada no índice do banco**. A rotina
detecta e avisa; sem isso o erro viria como um genérico "Item já existe".

---

## 6. Resultado e erros

A tela de resultado traz o resumo e a lista de linhas com problema — **linha,
produto e o motivo**, já em linguagem direta:

```
Linha  Produto      O que aconteceu
2      PA000001     B1_SEGUM: O campo Seg.Un.Medi. nao foi preenchido
5      PA000004     Este codigo pertence a um produto EXCLUIDO (registro 148828)
```

O log bruto do ExecAuto traz uma dezena de campos de rastreio (`Id do formulario
de origem`, `Valor anterior`…) que tornam a mensagem ilegível. `IP01Erro()`
extrai apenas o campo e a mensagem, e elimina repetições.

Cada linha roda em transação própria: uma rejeitada não derruba as demais.

O log completo fica em `\imp_produtos\log\zImpPro_AAAAMMDD_HHMMSS.log` e é
copiado para `C:\Erros Protheus` na máquina do usuário (constante `IMP_DIREST`).

---

## 7. Manutenção

```advpl
IP01Fixos()   // valores aplicados a todos os produtos
```

Aplicado apenas quando a coluna **não vem preenchida** no arquivo — o conteúdo do
arquivo sempre tem prioridade.

### Estrutura do fonte

| Bloco | Funções |
|---|---|
| Entrada | `zImpPro` · `IP01Fixos` |
| Tela | `IP01Tela` · `IP01Busca` · `IP01Importa` |
| Processamento | `IP01Proc` · `IP01Exec` · `IP01Erro` · `IP01Tag` · `IP01Rejeita` |
| Arquivo | `IP01LerArq` · `IP01EhUtf8` · `IP01Quebra` · `IP01Separ` · `IP01Split` |
| Layout | `IP01Mapa` · `IP01Dicio` · `IP01Reg` · `IP01Conv` · `IP01Num` · `IP01Data` |
| Resultado | `IP01Result` · `IP01Log` · `IP01RecDel` |

---

## 8. Conferir no banco

```sql
SELECT B1_COD, B1_DESC, B1_TIPO, B1_UM, B1_SEGUM, B1_LOCPAD,
       B1_GRUPO, B1_POSIPI, B1_ORIGEM, B1_PRV1, B1_CUSTD,
       B1_PICM, B1_IPI, B1_CONTA
  FROM SB1XXX
 WHERE D_E_L_E_T_ = ''
 ORDER BY R_E_C_N_O_ DESC;
```
