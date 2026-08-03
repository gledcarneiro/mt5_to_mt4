//+------------------------------------------------------------------+
//|                                         SignalSenderEA_MT5.mq5   |
//|                                  Copyright 2026, GledIA_Core    |
//|                                                                  |
//| MT5 to MT4 Bridge (ZeroMQ RAM Protocol) - Signal Sender EA       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, GledIA_Core"
#property link      ""
#property version   "1.00"
#property strict

// Include ZeroMQ bindings
#include <Zmq/Zmq.mqh>

//--- Input Parameters
input string   InpZmqHost        = "127.0.0.1";  // ZeroMQ Host (default: localhost)
input int      InpZmqPort        = 5555;         // ZeroMQ Port
input long     InpMagicNumber    = 40000100;     // Filter by Magic Number

//--- Global Variables
Context *zmq_context = NULL;
Socket  *zmq_socket  = NULL;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Initializing SignalSenderEA_MT5...");
   
   // Create ZMQ Context and Publisher Socket
   zmq_context = new Context();
   if(zmq_context == NULL)
   {
      Print("Error: Failed to create ZMQ context.");
      return INIT_FAILED;
   }
   
   zmq_socket = new Socket(zmq_context, ZMQ_PUB);
   if(zmq_socket == NULL || !zmq_socket.valid())
   {
      Print("Error: Failed to create ZMQ PUB socket.");
      return INIT_FAILED;
   }
   
   // Bind to local address
   string bind_addr = "tcp://" + InpZmqHost + ":" + IntegerToString(InpZmqPort);
   Print("Binding ZMQ socket to: ", bind_addr);
   
   if(!zmq_socket.bind(bind_addr))
   {
      Print("Error: Failed to bind ZMQ socket to ", bind_addr);
      return INIT_FAILED;
   }
   
   Print("SignalSenderEA_MT5 initialized and publishing on ", bind_addr);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Deinitializing SignalSenderEA_MT5. Reason code: ", reason);
   
   // Clean up socket and context
   if(zmq_socket != NULL)
   {
      delete zmq_socket;
      zmq_socket = NULL;
   }
   
   if(zmq_context != NULL)
   {
      delete zmq_context;
      zmq_context = NULL;
   }
   
   Print("SignalSenderEA_MT5 cleaned up successfully.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // No tick processing needed for pure event-driven signal sending
}

//+------------------------------------------------------------------+
//| Trade transaction function                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Handle new deals added to history
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong deal_ticket = trans.deal;
      if(HistoryDealSelect(deal_ticket))
      {
         long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         
         // Filter by Magic Number
         if(magic == InpMagicNumber)
         {
            string symbol  = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
            long entry     = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
            long type      = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
            double volume  = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
            long pos_id    = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
            datetime time  = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
            
            // Check if it's an entry or exit deal
            if(entry == DEAL_ENTRY_IN)
            {
               // Position Open
               string type_str = "";
               if(type == DEAL_TYPE_BUY)       type_str = "BUY";
               else if(type == DEAL_TYPE_SELL) type_str = "SELL";
               
               if(type_str != "")
               {
                  string json = StringFormat(
                     "{\"action\":\"OPEN\",\"type\":\"%s\",\"symbol\":\"%s\",\"lot\":%.2f,\"magic\":%I64d,\"mt5_ticket\":%I64d,\"timestamp\":%I64d}",
                     type_str, symbol, volume, magic, pos_id, (long)time
                  );
                  SendSignal(json);
               }
            }
            else if(entry == DEAL_ENTRY_OUT)
            {
               // Position Close
               // Check if there are still any other open positions for this magic and symbol
               // If none remain, we can send a CLOSE_ALL signal to allow atomic mass liquidation.
               // Otherwise, send a CLOSE_TICKET.
               bool has_remaining = HasRemainingPositions(symbol, magic);
               
               string json = "";
               if(!has_remaining)
               {
                  // Close All
                  json = StringFormat(
                     "{\"action\":\"CLOSE_ALL\",\"symbol\":\"%s\",\"magic\":%I64d,\"timestamp\":%I64d}",
                     symbol, magic, (long)time
                  );
               }
               else
               {
                  // Close Ticket
                  json = StringFormat(
                     "{\"action\":\"CLOSE_TICKET\",\"symbol\":\"%s\",\"magic\":%I64d,\"mt5_ticket\":%I64d,\"timestamp\":%I64d}",
                     symbol, magic, pos_id, (long)time
                  );
               }
               
               if(json != "")
               {
                  SendSignal(json);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if there are remaining open positions for symbol & magic   |
//+------------------------------------------------------------------+
bool HasRemainingPositions(string symbol, long magic)
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      string pos_symbol = PositionGetSymbol(i);
      if(pos_symbol == symbol)
      {
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         if(pos_magic == magic)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Send ZeroMQ signal                                               |
//+------------------------------------------------------------------+
void SendSignal(string payload)
{
   if(zmq_socket != NULL && zmq_socket.valid())
   {
      // Send message in non-blocking mode to prevent terminal freezing
      if(zmq_socket.send(payload, true))
      {
         Print("ZMQ Published Signal: ", payload);
      }
      else
      {
         Print("Error: ZMQ publish failed for payload: ", payload);
      }
   }
   else
   {
      Print("Error: ZMQ socket is not valid or initialized.");
   }
}
//+------------------------------------------------------------------+
