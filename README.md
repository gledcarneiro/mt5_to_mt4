# mt5_to_mt4
sincronizar sinais de trading entre terminais MetaTrader 5 e MetaTrader 4

# Visão Geral dos EAs de Sincronização de Sinais GledTrader

Este documento resume as funcionalidades e a interação entre os Expert Advisors `SignalReceiverEA_MT4.mq4` e `SignalSenderEA_MT5.mq5`, que operam como um sistema para sincronizar sinais de trading entre terminais MetaTrader 5 e MetaTrader 4 utilizando arquivos na pasta `Common\Files`.

---

## 1. `SignalReceiverEA_MT4.mq4` (Versão 2.9) 

Este EA atua como o "receptor" de sinais no MetaTrader 4. Sua função primária é processar sinais de negociação originados pelo seu script Python (via `SignalSenderEA_MT5`), que são entregues em arquivos JSON, gerenciando-os através de um arquivo de fila.

### Funcionalidades Principais:

* **Monitoramento da Fila de Sinais:** Monitora ativamente o arquivo `signal_queue.txt` localizado na pasta `Common\Files`.
* **Leitura e Processamento da Fila:** A cada tick do MT4, lê o conteúdo completo de `signal_queue.txt`, divide-o em nomes de arquivos de sinal, e itera sobre eles para processamento.
* **Ignora Sinais Temporários/Processados:** Automaticamente ignora nomes de arquivos que contêm ".tmp" ou ".json.processed" na fila, prevenindo reprocessamento e erros.
* **Processamento Individual de Sinais (`ProcessSingleSignalFile()`):**
    * Abre e lê o conteúdo de cada arquivo JSON de sinal.
    * Extrai informações como `signal_type`, `symbol`, `lot` e `magic_number` do JSON.
    * **Adaptação de Símbolo:** Converte "EURUSD" para "EURUSDc" (ou similar) se necessário, para compatibilidade com sufixos de corretoras no MT4.
    * **Filtro por Magic Number:** Verifica se o `magic_number` do sinal corresponde ao `InpMagicNumber` configurado. Sinais inválidos são ignorados e seus arquivos são marcados para renomeação.
    * **Execução de Ordens:** Realiza operações de `BUY`, `SELL`, `CLOSE_BUY`, e `CLOSE_SELL` com base no `signal_type` recebido.
* **Lógica de Renomeação e Remoção da Fila:**
    * Um sinal é considerado processado (e será removido da fila) **se a ordem de negociação foi executada com sucesso** (`trade_success` é `true`).
    * Após o processamento bem-sucedido da ordem, o EA tenta renomear o arquivo original do sinal para `nome_do_sinal.json.processed`.
    * **Renomeação Robusta (`RenameSignalFileAsProcessed()`):** Tenta renomear o arquivo múltiplas vezes (`InpMaxFileRenameRetries`) com um atraso. Considera sucesso se o arquivo já não existir (erro 4001 - `ERR_NO_FILE`), indicando que pode ter sido movido/deletado por outro processo.
    * Se a execução da ordem falha (`trade_success` é `false`), o sinal permanece na fila para reprocessamento.
* **Reescrita da Fila:** Após processar todos os sinais em uma rodada, o `signal_queue.txt` é reescrito contendo apenas os nomes dos arquivos que não foram processados com sucesso.

---

## 2. `SignalSenderEA_MT5.mq5` (Versão 1.12) 

Este EA é o "emissor" de sinais no MetaTrader 5. Sua responsabilidade é monitorar as operações de negociação (deals) abertas pelo seu script Python (identificadas por um Magic Number específico) e, com base nelas, gerar arquivos de sinal em formato JSON, adicionando-os a uma fila para que o MT4 possa consumi-los.

### Funcionalidades Principais:

* **Magic Number Centralizado:** Monitora e filtra apenas os negócios (deals) no MT5 que correspondem ao `InpMagicNumber` configurado, que deve ser o mesmo usado pelo script Python.
* **Inicialização e Informação de Caminho:** Ao ser inicializado (`OnInit()`), exibe as possíveis localizações da pasta `Common\Files` onde os sinais serão gravados e inicia o rastreamento do histórico de deals.
* **Detecção de Novos Negócios (`OnTick()` -> `ProcessNewDeals()`):** A cada tick, verifica se houve um aumento no número total de negócios no histórico recente. Se houver, ele processa apenas os deals mais novos.
* **Identificação de Tipos de Sinal:**
    * Detecta `DEAL_TYPE_BUY` com `DEAL_ENTRY_IN` para sinais de **BUY**.
    * Detecta `DEAL_TYPE_BUY` com `DEAL_ENTRY_OUT` para sinais de **CLOSE_SELL**.
    * Detecta `DEAL_TYPE_SELL` com `DEAL_ENTRY_IN` para sinais de **SELL**.
    * Detecta `DEAL_TYPE_SELL` com `DEAL_ENTRY_OUT` para sinais de **CLOSE_BUY**.
* **Geração de Sinais JSON:** Para cada deal relevante, constrói uma string JSON contendo o `signal_type`, `symbol`, `lot` (se aplicável), `magic_number` e um `timestamp`.
* **Envio de Sinal para Arquivo e Fila (`SendSignalToFile()`):** 
    * **Criação Segura de Arquivo:** Primeiro escreve o sinal JSON em um arquivo temporário (`.json.tmp`) para garantir que o arquivo final só seja visível quando completo.
    * **Renomeação Atômica:** Renomeia o arquivo temporário para o nome final (`.json`).
    * **Gerenciamento Robusto da Fila:**
        * Lê o conteúdo *atual* do `signal_queue.txt`.
        * Adiciona o nome do novo arquivo de sinal ao conteúdo lido, garantindo uma nova linha.
        * **Sobrescreve o `signal_queue.txt`** com o conteúdo completo e atualizado. Isso é fundamental para manter a fila consistente e evitar problemas de acesso concorrente ou dados desatualizados.
    * Inclui logs detalhados e tratamento de erros para cada etapa do processo de escrita e renomeação de arquivos.

---

## 3. Alinhamento e Sincronismo entre os EAs

A comunicação entre o SignalSender (MT5) e o SignalReceiver (MT4) é estabelecida através de um sistema de arquivos compartilhado, garantindo robustez e ordem na transmissão dos sinais:

* **Fluxo de Sinais:** O `SignalSenderEA_MT5` detecta um novo deal no MT5 (gerado pelo seu agente Python), cria um arquivo JSON com os detalhes do sinal e adiciona o nome desse arquivo ao `signal_queue.txt`. 
* **Consumo da Fila:** O `SignalReceiverEA_MT4` monitora o `signal_queue.txt`. Ele lê a fila, processa cada sinal em sua ordem, tenta executar as ordens correspondentes no MT4, e então reescreve o `signal_queue.txt` sem os nomes dos arquivos que já foram processados com sucesso. 
* **Filtragem por Magic Number:** Ambos os EAs utilizam o mesmo Magic Number (`InpMagicNumber`) para garantir que apenas os sinais e deals pertinentes à sua estratégia de IA sejam processados, ignorando operações de outros EAs ou operações manuais. 
* **Resiliência a Falhas de Arquivo:** O `SignalReceiverEA_MT4` é projetado para lidar com situações onde um arquivo de sinal não pode ser lido ou renomeado. Nesses casos, ele tenta renomear o arquivo para `.processed` e, se falhar, ainda assim marca o sinal como processado na fila para evitar que a fila "trave" devido a um arquivo problemático, garantindo a continuidade do processamento de outros sinais. A renomeação é desacoplada do sucesso de processamento do sinal na fila.
* **Atomicidade na Escrita:** O `SignalSenderEA_MT5` utiliza a estratégia de escrever para um arquivo temporário e depois renomeá-lo. Isso garante que o `SignalReceiverEA_MT4` nunca tente ler um arquivo JSON incompleto, garantindo a integridade dos dados do sinal.

---
