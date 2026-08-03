//+------------------------------------------------------------------+
//|                                       SignalReceiverEA_MT4.mq4   |
//|                                  Copyright 2026, GledIA_Core    |
//|                                                                  |
//| MT5 to MT4 Bridge (ZeroMQ RAM Protocol) - Signal Receiver EA     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, GledIA_Core"
#property link      ""
#property version   "1.00"
#property strict

// Include ZeroMQ bindings
#include <Zmq/Zmq.mqh>

//--- Input Parameters
input string   InpZmqHost        = "127.0.0.1";  // ZeroMQ Host
input int      InpZmqPort        = 5555;         // ZeroMQ Port
input string   InpSymbolSuffix   = "c";          // Suffix for Cent accounts (e.g. EURUSD -> EURUSDc)
input long     InpMagicNumber    = 40000100;     // Filter signals & trade with this Magic Number
input int      InpSlippage       = 3;            // Allowed Slippage in Points
input int      InpTimerInterval  = 10;           // Poll interval in Milliseconds (default: 10ms)
input int      InpMaxRetries     = 3;            // Max retries on execution failure

//--- Global Variables
Context *zmq_context = NULL;
Socket  *zmq_socket  = NULL;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Initializing SignalReceiverEA_MT4...");
   
   // Create ZMQ Context and Subscriber Socket
   zmq_context = new Context();
   if(zmq_context == NULL)
   {
      Print("Error: Failed to create ZMQ context.");
      return INIT_FAILED;
   }
   
   zmq_socket = new Socket(zmq_context, ZMQ_SUB);
   if(zmq_socket == NULL || !zmq_socket.valid())
   {
      Print("Error: Failed to create ZMQ SUB socket.");
      return INIT_FAILED;
   }
   
   // Connect to Publisher
   string conn_addr = "tcp://" + InpZmqHost + ":" + IntegerToString(InpZmqPort);
   Print("Connecting ZMQ SUB socket to: ", conn_addr);
   
   if(!zmq_socket.connect(conn_addr))
   {
      Print("Error: Failed to connect ZMQ socket to ", conn_addr);
      return INIT_FAILED;
   }
   
   // Subscribe to all topics (empty string subscribes to all messages)
   if(!zmq_socket.subscribe(""))
   {
      Print("Error: Failed to subscribe to ZMQ topics.");
      return INIT_FAILED;
   }
   
   // Set up Millisecond Timer
   if(!EventSetMillisecondTimer(InpTimerInterval))
   {
      Print("Error: Failed to set millisecond timer.");
      return INIT_FAILED;
   }
   
   Print("SignalReceiverEA_MT4 initialized. Listening on ", conn_addr, " with timer interval ", InpTimerInterval, "ms");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Deinitializing SignalReceiverEA_MT4. Reason code: ", reason);
   
   // Clean up timer
   EventKillTimer();
   
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
   
   Print("SignalReceiverEA_MT4 cleaned up successfully.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // No tick processing needed, timer-driven non-blocking polling is used
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(zmq_socket == NULL || !zmq_socket.valid()) return;
   
   // Retrieve all pending signals in the queue
   while(true)
   {
      ZmqMsg msg;
      // Use non-blocking read
      if(!zmq_socket.recv(msg, true))
      {
         break; // No more messages in queue
      }
      
      string payload = msg.getData();
      if(payload != "")
      {
         Print("ZMQ Received Signal: ", payload);
         ProcessSignal(payload);
      }
   }
}

//+------------------------------------------------------------------+
//| Process and route the received JSON signal                       |
//+------------------------------------------------------------------+
void ProcessSignal(string json)
{
   long magic = GetJsonLongValue(json, "magic");
   if(magic != InpMagicNumber)
   {
      // Ignore signals not matching our Magic Number
      return;
   }
   
   string action = GetJsonStringValue(json, "action");
   string symbol = GetJsonStringValue(json, "symbol");
   
   if(action == "OPEN")
   {
      string type      = GetJsonStringValue(json, "type");
      double lot       = GetJsonDoubleValue(json, "lot");
      long mt5_ticket  = GetJsonLongValue(json, "mt5_ticket");
      
      ExecuteOpen(symbol, type, lot, mt5_ticket);
   }
   else if(action == "CLOSE_TICKET")
   {
      long mt5_ticket  = GetJsonLongValue(json, "mt5_ticket");
      ExecuteCloseTicket(symbol, mt5_ticket);
   }
   else if(action == "CLOSE_ALL")
   {
      ExecuteCloseAll(symbol);
   }
}

//+------------------------------------------------------------------+
//| Execute OPEN order                                               |
//+------------------------------------------------------------------+
void ExecuteOpen(string symbol, string type, double lot, long mt5_ticket)
{
   string local_symbol = symbol + InpSymbolSuffix;
   
   // Verify symbol is available
   double ask = MarketInfo(local_symbol, MODE_ASK);
   double bid = MarketInfo(local_symbol, MODE_BID);
   if(ask <= 0 || bid <= 0)
   {
      Print("Error: Symbol ", local_symbol, " is not active or not in Market Watch.");
      return;
   }
   
   int cmd = -1;
   double price = 0.0;
   if(type == "BUY")
   {
      cmd = OP_BUY;
      price = ask;
   }
   else if(type == "SELL")
   {
      cmd = OP_SELL;
      price = bid;
   }
   else
   {
      Print("Error: Unknown order type: ", type);
      return;
   }
   
   // Include MT5 ticket in comment for identification
   string comment = "mt5_ticket:" + IntegerToString(mt5_ticket);
   
   int ticket = -1;
   for(int i = 0; i < InpMaxRetries; i++)
   {
      // Refresh rates for safety
      RefreshRates();
      price = (cmd == OP_BUY) ? MarketInfo(local_symbol, MODE_ASK) : MarketInfo(local_symbol, MODE_BID);
      
      ticket = OrderSend(local_symbol, cmd, lot, price, InpSlippage, 0, 0, comment, (int)InpMagicNumber, 0, clrGreen);
      if(ticket > 0)
      {
         Print("Success: Opened ", type, " order #", ticket, " for ", local_symbol, " (MT5 Ticket: ", mt5_ticket, ")");
         break;
      }
      else
      {
         int err = GetLastError();
         Print("Warning: OrderSend failed with error ", err, ". Attempt ", i+1, " of ", InpMaxRetries);
         Sleep(100);
      }
   }
   
   if(ticket <= 0)
   {
      Print("Error: Failed to open order after ", InpMaxRetries, " attempts.");
   }
}

//+------------------------------------------------------------------+
//| Execute CLOSE_TICKET order                                       |
//+------------------------------------------------------------------+
void ExecuteCloseTicket(string symbol, long mt5_ticket)
{
   string local_symbol = symbol + InpSymbolSuffix;
   int mt4_ticket = FindMT4TicketByMT5Ticket(mt5_ticket);
   
   if(mt4_ticket == -1)
   {
      Print("Warning: Could not find matching MT4 order for MT5 Ticket: ", mt5_ticket);
      return;
   }
   
   if(OrderSelect(mt4_ticket, SELECT_BY_TICKET))
   {
      int cmd = OrderType();
      double lot = OrderLots();
      
      bool success = false;
      for(int i = 0; i < InpMaxRetries; i++)
      {
         RefreshRates();
         double close_price = (cmd == OP_BUY) ? MarketInfo(local_symbol, MODE_BID) : MarketInfo(local_symbol, MODE_ASK);
         
         success = OrderClose(mt4_ticket, lot, close_price, InpSlippage, clrRed);
         if(success)
         {
            Print("Success: Closed MT4 order #", mt4_ticket, " (MT5 Ticket: ", mt5_ticket, ")");
            break;
         }
         else
         {
            int err = GetLastError();
            Print("Warning: OrderClose #", mt4_ticket, " failed with error ", err, ". Attempt ", i+1, " of ", InpMaxRetries);
            Sleep(100);
         }
      }
      
      if(!success)
      {
         Print("Error: Failed to close MT4 order #", mt4_ticket, " after ", InpMaxRetries, " attempts.");
      }
   }
}

//+------------------------------------------------------------------+
//| Execute CLOSE_ALL orders matching local symbol & magic           |
//+------------------------------------------------------------------+
void ExecuteCloseAll(string symbol)
{
   string local_symbol = symbol + InpSymbolSuffix;
   Print("Executing CLOSE_ALL for symbol: ", local_symbol);
   
   bool has_errors = false;
   
   // Loop backwards because we are modifying the order list
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == InpMagicNumber && OrderSymbol() == local_symbol)
         {
            int mt4_ticket = OrderTicket();
            int cmd = OrderType();
            double lot = OrderLots();
            
            bool success = false;
            for(int retry = 0; retry < InpMaxRetries; retry++)
            {
               RefreshRates();
               double close_price = (cmd == OP_BUY) ? MarketInfo(local_symbol, MODE_BID) : MarketInfo(local_symbol, MODE_ASK);
               
               success = OrderClose(mt4_ticket, lot, close_price, InpSlippage, clrRed);
               if(success)
               {
                  Print("Success: Closed order #", mt4_ticket, " in CLOSE_ALL cycle.");
                  break;
               }
               else
               {
                  int err = GetLastError();
                  Print("Warning: OrderClose #", mt4_ticket, " failed with error ", err, " in CLOSE_ALL. Attempt ", retry+1);
                  Sleep(100);
               }
            }
            
            if(!success)
            {
               has_errors = true;
               Print("Error: Failed to close order #", mt4_ticket, " in CLOSE_ALL cycle.");
            }
         }
      }
   }
   
   if(!has_errors)
   {
      Print("Success: CLOSE_ALL cycle completed successfully.");
   }
   else
   {
      Print("Warning: CLOSE_ALL cycle completed with some errors.");
   }
}

//+------------------------------------------------------------------+
//| Find MT4 Order Ticket mapping to MT5 Ticket                      |
//+------------------------------------------------------------------+
int FindMT4TicketByMT5Ticket(long mt5_ticket)
{
   string mt5_ticket_str = IntegerToString(mt5_ticket);
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == InpMagicNumber)
         {
            string comment = OrderComment();
            if(StringFind(comment, mt5_ticket_str) != -1)
            {
               return OrderTicket();
            }
         }
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Simple JSON parser helper: Get String value                      |
//+------------------------------------------------------------------+
string GetJsonStringValue(string json, string key)
{
   string key_pattern = "\"" + key + "\"";
   int pos = StringFind(json, key_pattern);
   if(pos == -1) return "";
   
   int colon_pos = StringFind(json, ":", pos + StringLen(key_pattern));
   if(colon_pos == -1) return "";
   
   int val_start = -1;
   int val_end = -1;
   
   int search_quote = StringFind(json, "\"", colon_pos + 1);
   int comma_pos = StringFind(json, ",", colon_pos + 1);
   int brace_pos = StringFind(json, "}", colon_pos + 1);
   
   int limit = (comma_pos != -1 && (brace_pos == -1 || comma_pos < brace_pos)) ? comma_pos : brace_pos;
   
   if(search_quote != -1 && (limit == -1 || search_quote < limit))
   {
      val_start = search_quote + 1;
      val_end = StringFind(json, "\"", val_start);
   }
   else
   {
      val_start = colon_pos + 1;
      while(val_start < StringLen(json) && (StringGetCharacter(json, val_start) == ' ' || StringGetCharacter(json, val_start) == '\t'))
      {
         val_start++;
      }
      val_end = limit;
      if(val_end == -1) val_end = StringLen(json);
      while(val_end > val_start && (StringGetCharacter(json, val_end - 1) == ' ' || StringGetCharacter(json, val_end - 1) == '\r' || StringGetCharacter(json, val_end - 1) == '\n'))
      {
         val_end--;
      }
   }
   
   if(val_start != -1 && val_end != -1 && val_end > val_start)
   {
      return StringSubstr(json, val_start, val_end - val_start);
   }
   return "";
}

//+------------------------------------------------------------------+
//| Simple JSON parser helper: Get Double value                      |
//+------------------------------------------------------------------+
double GetJsonDoubleValue(string json, string key)
{
   string val = GetJsonStringValue(json, key);
   if(val == "") return 0.0;
   return StringToDouble(val);
}

//+------------------------------------------------------------------+
//| Simple JSON parser helper: Get Long value                        |
//+------------------------------------------------------------------+
long GetJsonLongValue(string json, string key)
{
   string val = GetJsonStringValue(json, key);
   if(val == "") return 0;
   return StringToInteger(val);
}
//+------------------------------------------------------------------+
