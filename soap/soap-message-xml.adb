------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                         Copyright (C) 2000-2001                          --
--                                ACT-Europe                                --
--                                                                          --
--  Authors: Dmitriy Anisimov - Pascal Obry                                 --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

--  $Id$

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded;
with Ada.Exceptions;

with Input_Sources.Strings;
with Sax.Readers;
with Sax.Attributes;
with Unicode.CES.Basic_8bit;

with SOAP.Types;
with SOAP.Message.Payload;
with SOAP.Message.Response;
with SOAP.Message.Error;

package body SOAP.Message.XML is

   use Ada.Strings.Unbounded;

   NL         : constant String := ASCII.CR & ASCII.LF;

   XML_Header : constant String := "<?xml version=""1.0""?>";

   URL_Enc    : constant String := "http://schemas.xmlsoap.org/soap/encoding/";
   URL_Env    : constant String := "http://schemas.xmlsoap.org/soap/envelope/";
   URL_xsd    : constant String := "http://www.w3.org/1999/XMLSchema";
   URL_xsi    : constant String := "http://www.w3.org/1999/XMLSchema-instance";

   Start_Env  : constant String := "<SOAP-ENV:Envelope";
   End_Env    : constant String := "</SOAP-ENV:Envelope>";

   Header     : constant String
     := Start_Env & ' '
     & "SOAP-ENV:encodingStyle=""" & URL_Enc & """ "
     & "xmlns:SOAP-ENC=""" & URL_Enc & """ "
     & "xmlns:SOAP-ENV=""" & URL_Env & """ "
     & "xmlns:xsd=""" & URL_xsd & """ "
     & "xmlns:xsi=""" & URL_xsi & """>";

   Start_Body      : constant String := "<SOAP-ENV:Body>";
   End_Body        : constant String := "</SOAP-ENV:Body>";

   Start_Fault_Env : constant String := "<SOAP-ENV:Fault>";

   ----------------
   -- Characters --
   ----------------

   procedure Characters
     (Handler : in out SOAP_Reader;
      Ch      :        Unicode.CES.Byte_Sequence)
   is
      use SOAP.Types;
      use type SOAP.Parameters.Set;
   begin
      if Handler.S = P_Int then
         Handler.Parameters := Handler.Parameters
           & I (To_String (Handler.Last_Name), Integer'Value (Ch));

      elsif Handler.S = P_Float then
         Handler.Parameters := Handler.Parameters
           & F (To_String (Handler.Last_Name), Float'Value (Ch));

      elsif Handler.S = P_Str then
         if Handler.Last_Str /= Null_Unbounded_String then
            Append (Handler.Last_Str, ' ');
         end if;

         Append (Handler.Last_Str, Ch);

      else
         Put_Line ("Not recognized " & Ch & " - " & State'Image (Handler.S));
      end if;
   end Characters;

   -----------------
   -- End_Element --
   -----------------

   procedure End_Element
     (Handler       : in out SOAP_Reader;
      Namespace_URI : in     Unicode.CES.Byte_Sequence := "";
      Local_Name    : in     Unicode.CES.Byte_Sequence := "";
      Qname         : in     Unicode.CES.Byte_Sequence := "")
   is
      use SOAP.Types;
      use type SOAP.Parameters.Set;
   begin
      if Handler.S in State_Param
        and then Local_Name = To_String (Handler.Wrapper_Name)
      then
         Handler.S := E_Wrap;

      elsif Handler.S = E_Wrap and then Local_Name = "Body" then
         Handler.S := E_Body;

      elsif Handler.S = E_Body and then Local_Name = "Envelope" then
         Handler.S := E_Env;

      elsif Handler.S in State_Param then

         if Handler.S = P_Str then
            Handler.Parameters := Handler.Parameters
              & S (To_String (Handler.Last_Name),
                   To_String (Handler.Last_Str));

            Handler.Last_Str := Null_Unbounded_String;
         end if;

      else
         Ada.Exceptions.Raise_Exception
           (Types.Data_Error'Identity,
            "End element " & Local_Name
            & " while on state " & State'Image (Handler.S));
      end if;
   end End_Element;

   -----------
   -- Image --
   -----------

   function Image (O : in Object'Class) return String is
   begin
      return To_String (XML.Image (O));
   end Image;

   -----------
   -- Image --
   -----------

   function Image (O : in Object'Class) return Unbounded_String is
      Message_Body : Unbounded_String;
   begin
      --  Header

      Append (Message_Body, XML_Header & NL);
      Append (Message_Body, Header & NL);

      --  Body

      Append (Message_Body, Start_Body & NL);

      --  Wrapper

      Append (Message_Body, Message.XML_Image (O));

      --  End of Body and Envelope

      Append (Message_Body, End_Body & NL);
      Append (Message_Body, End_Env & NL);

      return Message_Body;
   end Image;

   --------------
   -- Is_Error --
   --------------

   function Is_Error (Handler : in SOAP_Reader) return Boolean is
   begin
      return False;
   end Is_Error;

   function Is_Error (Handler : in Payload_Reader) return Boolean is
   begin
      return False;
   end Is_Error;

   function Is_Error (Handler : in Response_Reader) return Boolean is
   begin
      return Handler.Is_Error;
   end Is_Error;

   ------------------
   -- Load_Payload --
   ------------------

   function Load_Payload (XML : in String) return Message.Payload.Object is
      use Input_Sources.Strings;

      Str    : aliased String := XML;

      Source : String_Input;
      Reader : Payload_Reader;
   begin
      Open (Str'Unchecked_Access,
            Unicode.CES.Basic_8bit.Basic_8bit_Encoding,
            Source);

      --  If True, xmlns:* attributes will be reported in Start_Element
      Set_Feature (Reader, Sax.Readers.Namespace_Prefixes_Feature, True);
      Set_Feature (Reader, Sax.Readers.Validation_Feature, False);

      Parse (Reader, Source);
      Close (Source);

      Message.Set_Parameters (Reader.Payload, Reader.Parameters);

      return Reader.Payload;
   end Load_Payload;

   -------------------
   -- Load_Response --
   -------------------

   function Load_Response
     (XML : in String)
     return Message.Response.Object'Class
   is
      use Input_Sources.Strings;

      Str    : aliased String := XML;

      Source : String_Input;
      Reader : Response_Reader;
   begin
      Open (Str'Unchecked_Access,
            Unicode.CES.Basic_8bit.Basic_8bit_Encoding,
            Source);

      --  If True, xmlns:* attributes will be reported in Start_Element
      Set_Feature (Reader, Sax.Readers.Namespace_Prefixes_Feature, True);
      Set_Feature (Reader, Sax.Readers.Validation_Feature, False);

      Parse (Reader, Source);
      Close (Source);

      Message.Set_Parameters (Reader.Response, Reader.Parameters);

      if Reader.Is_Error then
         return Reader.Response;

      else
         --  Check that there is only one parameter

         if SOAP.Parameters.Argument_Count (Reader.Parameters) /= 1 then
            return Message.Error.Build
              (Message.Error.Client,
               "more than one parameters returned");
         end if;

         return Message.Response.Object (Reader.Response);
      end if;
   end Load_Response;

   ----------------------
   -- Set_Wrapper_Name --
   ----------------------

   procedure Set_Wrapper_Name
     (Handler : in out SOAP_Reader;
      Name    : in     String) is
   begin
      Handler.Wrapper_Name := To_Unbounded_String (Name);
   end Set_Wrapper_Name;

   procedure Set_Wrapper_Name
     (Handler : in out Payload_Reader;
      Name    : in     String) is
   begin
      SOAP.Message.Payload.Set_Procedure_Name (Handler.Payload, Name);
      Set_Wrapper_Name (SOAP_Reader (Handler), Name);
   end Set_Wrapper_Name;

   procedure Set_Wrapper_Name
     (Handler : in out Response_Reader;
      Name    : in     String) is
   begin
      if Name = "Fault" then
         Handler.Is_Error := True;
      else
         SOAP.Message.Set_Wrapper_Name (Handler.Response, Name);
      end if;

      Set_Wrapper_Name (SOAP_Reader (Handler), Name);
   end Set_Wrapper_Name;

   -------------------
   -- Start_Element --
   -------------------

   procedure Start_Element
     (Handler       : in out SOAP_Reader;
      Namespace_URI : in     Unicode.CES.Byte_Sequence       := "";
      Local_Name    : in     Unicode.CES.Byte_Sequence       := "";
      Qname         : in     Unicode.CES.Byte_Sequence       := "";
      Atts          : in     Sax.Attributes.Attributes'Class)
   is
      procedure Read_Parameters;

      procedure Read_Parameters is
         N : constant Natural := Sax.Attributes.Get_Length (Atts);
         K : Natural := 0;
      begin
         Handler.Last_Name := To_Unbounded_String (Local_Name);

         if Is_Error (SOAP_Reader'Class (Handler)) then
            Handler.S := P_Str;

         else

            while K <= N
              and then Sax.Attributes.Get_Qname (Atts, K) /= "xsi:type"
            loop
               K := K + 1;
            end loop;

            if K > N then
               --  xsi:type not found
               raise Constraint_Error;

            else
               declare
                  xsi_type : constant String
                    := Sax.Attributes.Get_Value (Atts, K);
               begin
                  if xsi_type = SOAP.Types.XML_Int then
                     Handler.S := P_Int;

                  elsif xsi_type = SOAP.Types.XML_Float then
                     Handler.S := P_Float;

                  elsif xsi_type = SOAP.Types.XML_String then
                     Handler.S := P_Str;
                  end if;
               end;
            end if;
         end if;
      end Read_Parameters;


   begin
      if Local_Name = "Envelope" and then Handler.S = Start then
         Handler.S := S_Env;

      elsif Local_Name = "Body" and then Handler.S = S_Env then
         Handler.S := S_Body;

      elsif Handler.S = S_Body then
         --  This is the procedure name
         Set_Wrapper_Name (SOAP_Reader'Class (Handler), Local_Name);
         Handler.S := S_Wrap;

      elsif Handler.S in S_Wrap .. State'Pred (E_Wrap) then
         --  This is the parameters

         Read_Parameters;

      else
         raise Constraint_Error;

      end if;
   end Start_Element;

end SOAP.Message.XML;
