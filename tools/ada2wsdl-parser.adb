------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                            Copyright (C) 2003                            --
--                                ACT-Europe                                --
--                                                                          --
--  Authors: Dmitriy Anisimkov - Pascal Obry                                --
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

with Ada.Text_IO;
with Ada.Exceptions;
with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

with GNAT.OS_Lib;

with Asis;
with Asis.Ada_Environments;
with Asis.Compilation_Units;
with Asis.Declarations;
with Asis.Definitions;
with Asis.Elements;
with Asis.Errors;
with Asis.Exceptions;
with Asis.Extensions.Flat_Kinds;
with Asis.Expressions;
with Asis.Implementation;
with Asis.Iterator;
with Asis.Text;

with A4G.GNAT_Int;

with Ada2WSDL.Options;
with Ada2WSDL.Generator;

package body Ada2WSDL.Parser is

   use Ada;
   use Ada.Exceptions;
   use Ada.Strings.Unbounded;
   use GNAT;

   use type Asis.Errors.Error_Kinds;

   subtype String_Access is OS_Lib.String_Access;

   ------------------------------
   -- File and Directory names --
   ------------------------------

   Tree_Name : String_Access;
   --  We need it in more, then one routine, so we define it here

   Max_Argument : constant := 1_000;

   Arg_List  : OS_Lib.Argument_List (1 .. Max_Argument);
   --  -I options from the Ada2WSDL command line transformed into the
   --  form appropriate for calling gcc to create the tree file.

   Arg_Index : Natural := 0;

   ----------------------
   -- Status variables --
   ----------------------

   My_Context : Asis.Context;

   Tree_File  : Text_IO.File_Type;
   Spec_File  : Text_IO.File_Type;

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure Create_Tree;
   --  Creates a tree file or checks if the tree file already exists,
   --  depending on options

   type Element_Node;
   type Link is access all Element_Node;

   type Element_Node is record
      Spec      : Asis.Element := Nil_Element;
      Spec_Name : String_Access;
      --  Not used for incomplete type declarations
      Up        : Link;
      Down      : Link;
      Prev      : Link;
      Next      : Link;
      Last      : Link;
   end record;
   --  An element of a dynamic structure representing a "skeleton" of the body
   --  to be generated
   --
   --  Logically this structure is a list of elements representing local
   --  bodies and sublists representing the bodies which are a components of
   --  some local body. Each list and sublist is represented by its first
   --  element. For this first list element, the field Last is used to point
   --  to the last element in this list to speed up adding the new element if
   --  we do not have to order alphabetically the local bodies.

   Body_Structure : aliased Element_Node;
   --  This is a "design" for a body to generate. It contains references
   --  to the elements from the argument spec for which body samples should
   --  be generated, ordered alphabetically. The top of this link structure
   --  is the Element representing a unit declaration from the argument
   --  compilation unit.

   ------------------------------------------------
   -- Actuals for Traverse_Element instantiation --
   ------------------------------------------------

   type Body_State is record
      Argument_Spec   : Boolean := True;
      --  Flag indicating if we are in the very beginning (very top)
      --  of scanning the argument library unit declaration

      Current_List    : Link;
      --  Declaration list in which a currently processed spec
      --  should be inserted;


      Last_Top        : Link;
      --  An element which represents a declaration from which the currently
      --  processed sublist was originated

      New_List_Needed : Boolean := False;
      --  Flag indication if a new sublist should be created
   end record;

   procedure Create_Element_Node
     (Element : in     Asis.Element;
      Control : in out Traverse_Control;
      State   : in out Body_State);
   --  When visiting an Element representing something for which a body
   --  sample may be required, we check if the body is really required
   --  and insert the corresponding Element on the right place in Body_State
   --  if it is.

   procedure Go_Up
     (Element : in     Asis.Element;
      Control : in out Traverse_Control;
      State   : in out Body_State);
   --  When leaving a [generic] package declaration or a protected [type]
   --  declaration, we have to go one step up in Body_State structure.

   procedure Create_Structure is new Iterator.Traverse_Element
     (State_Information => Body_State,
      Pre_Operation     => Create_Element_Node,
      Post_Operation    => Go_Up);
   --  Creates Body_Structure by traversing an argument spec and choosing
   --  specs to create body samples for

   --------------------
   -- Local Routines --
   --------------------

   function Name (Elem : in Asis.Element) return String;
   --  Returns a defining name string image for a declaration which
   --  defines exactly one name. This should definitely be made an extension
   --  query

   procedure Analyse_Structure;
   --  Go through all entities and generate WSDL

   procedure Emergency_Clean_Up;
   --  Does clean up actions in case if an exception was raised during
   --  creating a body sample (closes a Context, dissociates it, finalizes
   --  ASIS, closes and deletes needed files.

   ------------------------------------
   -- Deffered Asis types to analyse --
   ------------------------------------

   type Element_Set is array (Positive range <>) of Asis.Element;

   Max_Deferred_Types : constant := 100;

   Deferred_Types : Element_Set (1 .. Max_Deferred_Types);
   --  Records all types not yet analysed when parsing formal
   --  parameters. This is needed as we can't parse a type while
   --  parsing the spec.

   Index          : Natural := 0;
   --  Current Index in the Deferred_Types array

   ----------------
   -- Add_Option --
   ----------------

   procedure Add_Option (Option : in String) is
   begin
      Arg_Index := Arg_Index + 1;
      Arg_List (Arg_Index) := new String'(Option);
   end Add_Option;

   -----------------------
   -- Analyse_Structure --
   -----------------------

   procedure Analyse_Structure is

      procedure Analyse_Package (Node : in Link);
      --  Analyse a package declaration, the package name is used as
      --  the Web Service name.

      procedure Analyse_Routine (Node : in Link);
      --  Node is a procedure or function, analyse its spec profile

      procedure Analyse_Type (Elem : in Asis.Element);
      --  Node is a subtype or type, analyse its definition

      procedure Analyse_Profile (Node : in Link);
      --  Generates an entry_body_formal_part, parameter or parameter
      --  and result profile for the body of a program unit
      --  represented by Node. Upon exit, sets Change_Line is set True
      --  if the following "is" for the body should be generated on a new line

      function Image (Str : in Wide_String) return String;
      --  Returns the trimed string representation of Str

      function Type_Name (Elem : in Asis.Element) return String;
      --  Returns the type name for Elem

      procedure Analyse_Node (Node : in Link);
      --  Analyse a Node, handles procedure or function only

      procedure Analyse_Node_List (List : in Link);
      --  Call Analyse_Node for each element in List

      ------------------
      -- Analyse_Node --
      ------------------

      procedure Analyse_Node (Node : in Link) is
         use Extensions.Flat_Kinds;

         Arg_Kind : constant Flat_Element_Kinds
           := Flat_Element_Kind (Node.Spec);
      begin
         case Arg_Kind is

            when A_Function_Declaration
              | A_Generic_Function_Declaration
              | A_Procedure_Declaration
              | A_Generic_Procedure_Declaration
              =>
               Analyse_Routine (Node);

            when An_Entry_Declaration
              | A_Single_Protected_Declaration
              | A_Protected_Type_Declaration
              | A_Single_Task_Declaration
              | A_Task_Type_Declaration
              | A_Generic_Package_Declaration
              | An_Incomplete_Type_Declaration
              =>
               null;

            when A_Package_Declaration =>
               Analyse_Package (Node);

            when A_Subtype_Declaration =>
               null;

            when An_Ordinary_Type_Declaration =>
               Analyse_Type (Node.Spec);

            when others =>
               Text_IO.Put_Line
                 (Text_IO.Standard_Error,
                  "ada2wsdl: unexpected element in the body structure");
               Text_IO.Put
                 (Text_IO.Standard_Error,
                  "ada2wsdl: " & Arg_Kind'Img);
               raise Fatal_Error;
         end case;

         if Node.Down /= null then
            Analyse_Node_List (Node.Down);
         end if;
      end Analyse_Node;

      -----------------------
      -- Analyse_Node_List --
      -----------------------

      procedure Analyse_Node_List (List : in Link) is
         Next_Node  : Link;
         List_Start : Link := List;
      begin
         --  Here we have to go to the beginning of the list

         while List_Start.Prev /= null loop
            List_Start := List_Start.Prev;
         end loop;

         Next_Node := List_Start;

         loop
            Analyse_Node (Next_Node);

            if Next_Node.Next /= null then
               Next_Node := Next_Node.Next;
            else
               exit;
            end if;

         end loop;

         --  Finalizing the enclosing construct:
         Next_Node := Next_Node.Up;
      end Analyse_Node_List;

      ---------------------
      -- Analyse_Package --
      ---------------------

      procedure Analyse_Package (Node : in Link) is
      begin
         if Options.WS_Name = Null_Unbounded_String then
            Options.WS_Name := To_Unbounded_String (Node.Spec_Name.all);
         end if;
      end Analyse_Package;

      ----------------------
      -- Analyse_Profile --
      ----------------------

      procedure Analyse_Profile (Node : in Link) is

         use Extensions.Flat_Kinds;

         Arg_Kind   : constant Flat_Element_Kinds
           := Flat_Element_Kind (Node.Spec);

         Parameters : constant Asis.Element_List
           := Declarations.Parameter_Profile (Node.Spec);

      begin
         if not Elements.Is_Nil (Parameters) then

            for I in Parameters'Range loop
               declare
                  Elem  : constant Asis.Element
                    := Declarations.Declaration_Subtype_Mark (Parameters (I));

                  Mode : constant Asis.Mode_Kinds
                    := Elements.Mode_Kind (Parameters (I));

                  Names : constant Defining_Name_List
                    := Declarations.Names (Parameters (I));
               begin
                  --  For each name create a new formal parameter

                  if not (Mode = An_In_Mode) then
                     Raise_Spec_Error
                       (Parameters (I),
                        Message => "only in mode supported.");
                  end if;

                  for K in Names'Range loop
                     Generator.New_Formal
                       (Var_Name => Image (Text.Element_Image (Names (K))),
                        Var_Type => Type_Name (Elem));
                  end loop;
               end;
            end loop;
         end if;

         if Arg_Kind = A_Function_Declaration
           or else Arg_Kind = A_Generic_Function_Declaration
         then
            declare
               Elem : constant Asis.Element
                 := Declarations.Result_Profile (Node.Spec);
            begin
               Generator.Return_Type (Type_Name (Elem));
            end;
         end if;
      end Analyse_Profile;

      ---------------------
      -- Analyse_Routine --
      ---------------------

      procedure Analyse_Routine (Node : in Link) is
         use Extensions.Flat_Kinds;

         Arg_Kind : constant Flat_Element_Kinds
           := Flat_Element_Kind (Node.Spec);
      begin
         begin
            if Arg_Kind = A_Function_Declaration then
               Generator.Start_Routine (Node.Spec_Name.all, "function ");
            else
               Generator.Start_Routine (Node.Spec_Name.all, "procedure");
            end if;
         exception
            when E : Spec_Error =>
               Raise_Spec_Error (Node.Spec, Exception_Message (E));
         end;

         Analyse_Profile (Node);
      end Analyse_Routine;

      ------------------
      -- Analyse_Type --
      ------------------

      procedure Analyse_Type (Elem : in Asis.Definition) is

         use Extensions.Flat_Kinds;

         procedure Analyse_Field (Component : in Asis.Element);
         --  Analyse a field from the record

         -------------------
         -- Analyse_Field --
         -------------------

         procedure Analyse_Field (Component : in Asis.Element) is
            Elem  : constant Asis.Element
              := Definitions.Subtype_Mark
                   (Definitions.Component_Subtype_Indication
                      (Declarations.Object_Declaration_View (Component)));

            Names : constant Defining_Name_List
              := Declarations.Names (Component);
         begin
            for K in Names'Range loop
               Generator.New_Component
                 (Comp_Name => Image (Text.Element_Image (Names (K))),
                  Comp_Type => Type_Name (Elem));
            end loop;
         end Analyse_Field;

         E : Asis.Definition := Declarations.Type_Declaration_View (Elem);

         Type_Kind : constant Flat_Element_Kinds := Flat_Element_Kind (E);

      begin
         case Type_Kind is

            when A_Record_Type_Definition =>

               Generator.Start_Record
                 (Image (Text.Element_Image (Declarations.Names (Elem)(1))));

               E := Definitions.Record_Definition (E);

               declare
                  R : constant Asis.Record_Component_List
                    := Definitions.Record_Components (E);
               begin
                  for K in R'Range loop
                     Analyse_Field (R (K));
                  end loop;
               end;

            when An_Unconstrained_Array_Definition
              | A_Constrained_Array_Definition
              =>

               E := Definitions.Array_Component_Definition (E);

               Generator.Start_Array
                 (Image (Text.Element_Image (Declarations.Names (Elem)(1))),
                  Image (Text.Element_Image (E)));
            when others =>
               --  A type definition not handled by this version
               null;
         end case;
      end Analyse_Type;

      -----------
      -- Image --
      -----------

      function Image (Str : in Wide_String) return String is
      begin
         return Strings.Fixed.Trim
           (Characters.Handling.To_String (Str), Strings.Both);
      end Image;

      ---------------
      -- Type_Name --
      ---------------

      function Type_Name (Elem : in Asis.Element) return String is
         use Extensions.Flat_Kinds;

         function Check_Float (Type_Name : in String) return String;
         --  Returns Type_Name, issue a warning if Type_Name is a Float

         -----------------
         -- Check_Float --
         -----------------

         function Check_Float (Type_Name : in String) return String is
            L_Name : constant String
              := Characters.Handling.To_Lower (Type_Name);
         begin
            if L_Name = "float" then
               Text_IO.Put_Line
                 (Text_IO.Standard_Error,
                  "ada2wsdl:" & Location (Elem)
                    & ": use Long_Float instead of Float for SOAP/WSDL"
                    & " items.");
            end if;

            return Type_Name;
         end Check_Float;

         E   : Asis.Element := Elem;
         CFS : Asis.Declaration;
      begin
         if Elements.Expression_Kind (E) = A_Selected_Component then
            E := Expressions.Selector (E);
         end if;

         CFS := Declarations.Corresponding_First_Subtype
           (Expressions.Corresponding_Name_Declaration (E));

         --  Get type view

         E := Declarations.Type_Declaration_View (CFS);

         if Flat_Element_Kind (E) = A_Record_Type_Definition then
            --  This is a record, checks if the record definition has
            --  been parsed.

            declare
               Name : constant String
                 := Image (Text.Element_Image (Declarations.Names (CFS) (1)));
            begin
               if not Generator.Record_Exists (Name) then
                  Index := Index + 1;
                  Deferred_Types (Index) := CFS;
               end if;

               return Name;
            end;

         else
            --  A simple type

            E := Declarations.Names (CFS) (1);

            declare
               E_Str : constant String := Image (Text.Element_Image (E));
            begin
               --  ??? There is probably a better way to achieve this
               if E_Str = "" then
                  return Check_Float (Image (Text.Element_Image (Elem)));
               else
                  return Check_Float (E_Str);
               end if;
            end;
         end if;
      end Type_Name;

   begin
      Analyse_Node (Body_Structure'Access);

      --  Analyse deferred types

      for K in 1 .. Index loop
         Analyse_Type (Deferred_Types (K));
      end loop;
   end Analyse_Structure;

   --------------
   -- Clean_Up --
   --------------

   procedure Clean_Up is
   begin
      --  Deleting the tree file itself

      Text_IO.Open (Tree_File, Text_IO.In_File, Tree_Name.all);

      Text_IO.Delete (Tree_File);

      --  Deleting the ALI file which was created along with the tree file
      --  We use the modified Tree_Name for this, because we do not need
      --  Tree_Name any more

      Tree_Name (Tree_Name'Last - 2 .. Tree_Name'Last) := "ali";

      Text_IO.Open (Tree_File, Text_IO.In_File, Tree_Name.all);
      Text_IO.Delete (Tree_File);

   exception
      when others =>
         null;
   end Clean_Up;

   -------------------------
   -- Create_Element_Node --
   -------------------------

   procedure Create_Element_Node
     (Element : in     Asis.Element;
      Control : in out Traverse_Control;
      State   : in out Body_State)
   is
      use Extensions.Flat_Kinds;

      Arg_Kind : constant Flat_Element_Kinds := Flat_Element_Kind (Element);

      Current_Node : Link;

      procedure Insert_In_List
        (State    : in out Body_State;
         El       : in     Asis.Element;
         New_Node :     out Link);
      --  Inserts an argument Element in the current list, keeping the
      --  alphabetic ordering. Creates a new sublist if needed.
      --  New_Node returns the reference to the newly inserted node

      --------------------
      -- Insert_In_List --
      --------------------

      procedure Insert_In_List
        (State    : in out Body_State;
         El       : in     Asis.Element;
         New_Node :    out Link) is
      begin
         New_Node      := new Element_Node;
         New_Node.Spec := El;

         New_Node.Spec_Name := new String'(Name (El));

         if State.New_List_Needed then
            --  here we have to set up a new sub-list:
            State.Current_List    := New_Node;
            New_Node.Up           := State.Last_Top;
            State.Last_Top.Down   := New_Node;
            State.New_List_Needed := False;

            New_Node.Last := New_Node;
            --  We've just created a new list. It contains a single element
            --  which is its last Element, so we are setting the link to the
            --  last element to the Prev field of the list head element

         else
            --  here we have to insert New_Node in an existing list,
            --  keeping the alphabetical order of program unit names

            New_Node.Up := State.Current_List.Up;

            if Arg_Kind = An_Incomplete_Type_Declaration then
               --  no need for alphabetical ordering, inserting in the
               --  very beginning:

               New_Node.Last := State.Current_List.Last;
               --  New_Node will be the head element of the list, so we have
               --  to copy into this new head element the reference to the
               --  last element of the list.

               New_Node.Next           := State.Current_List;
               State.Current_List.Prev := New_Node;
               State.Current_List      := New_Node;
            else

               New_Node.Prev                := State.Current_List.Last;
               State.Current_List.Last.Next := New_Node;
               State.Current_List.Last      := New_Node;
            end if;

         end if;
      end Insert_In_List;

      --  start of the processing of Create_Element_Node

   begin

      if State.Argument_Spec then
         Body_Structure.Spec      := Element;
         State.Argument_Spec      := False;
         Body_Structure.Spec_Name := new String'(Name (Element));
         Current_Node             := Body_Structure'Access;

      elsif Arg_Kind = A_Defining_Identifier then
         --  Skipping a defining name of a spec which may contain local
         --  specs requiring bodies
         null;

      elsif Arg_Kind = A_Protected_Definition then
         --  We just have to go one level down to process protected items
         null;

      elsif not (Arg_Kind = A_Procedure_Declaration
                   or else Arg_Kind = A_Function_Declaration
                   or else Arg_Kind = A_Subtype_Declaration
                   or else Arg_Kind = An_Ordinary_Type_Declaration
                   or else Arg_Kind = A_Package_Declaration)
      then
         --  Do nothing if this is not a procedure or function
         null;

      else
         Insert_In_List (State, Element, Current_Node);
      end if;

      if Arg_Kind = A_Package_Declaration
        or else Arg_Kind = A_Generic_Package_Declaration
        or else Arg_Kind = A_Single_Protected_Declaration
        or else Arg_Kind = A_Protected_Type_Declaration
      then
         --  here we may have specs requiring bodies inside a construct
         State.New_List_Needed := True;
         State.Last_Top        := Current_Node;

      elsif Arg_Kind = A_Protected_Definition then
         --  we have to skip this syntax level
         null;

      else
         --  no need to go deeper
         Control := Abandon_Children;
      end if;

   end Create_Element_Node;

   -----------------
   -- Create_Tree --
   -----------------

   procedure Create_Tree is

      File_Name : String_Access;
      Success   : Boolean := False;

      function Get_Tree_Name return String;
      --  Returns the name of the tree file

      ----------
      -- Free --
      ----------

      procedure Free is new Ada.Unchecked_Deallocation (String, String_Access);

      -------------------
      -- Get_Tree_Name --
      -------------------

      function Get_Tree_Name return String is
         F_Name      : constant String := To_String (Options.File_Name);
         Dot_Index   : Natural;
         Slash_Index : Natural;
         First, Last : Natural;

      begin
         Slash_Index := Strings.Fixed.Index (F_Name, "/");
         Dot_Index   := Strings.Fixed.Index (F_Name, ".", Strings.Backward);

         First := Natural'Max (F_Name'First, Slash_Index + 1);

         if Dot_Index = 0 then
            Last := F_Name'Last;
         else
            Last := Dot_Index - 1;
         end if;

         return F_Name (First .. Last) & ".adt";
      end Get_Tree_Name;


   begin
      File_Name := new String'(To_String (Options.File_Name));

      A4G.GNAT_Int.Compile
        (File_Name, Arg_List (Arg_List'First .. Arg_Index), Success);

      Tree_Name := new String'(Get_Tree_Name);

      if not Success then
         Text_IO.Put_Line
           (Text_IO.Standard_Error,
            "ada2wsdl: cannot create the tree file for " & File_Name.all);
         raise Parameter_Error;
      end if;

      Free (File_Name);
   end Create_Tree;

   ------------------------
   -- Emergency_Clean_Up --
   ------------------------

   procedure Emergency_Clean_Up is
   begin
      if Ada_Environments.Is_Open (My_Context) then
         Ada_Environments.Close (My_Context);
      end if;

      Ada_Environments.Dissociate (My_Context);

      Implementation.Finalize;

      if Text_IO.Is_Open (Spec_File) then
         --  No need to keep a broken body in case of an emergency clean up
         Text_IO.Close (Spec_File);
      end if;
   end Emergency_Clean_Up;

   -----------
   -- Go_Up --
   -----------

   procedure Go_Up
     (Element : in     Asis.Element;
      Control : in out Traverse_Control;
      State   : in out Body_State)
   is
      pragma Unreferenced (Control);

      use Extensions.Flat_Kinds;

      Arg_Kind : constant Flat_Element_Kinds := Flat_Element_Kind (Element);
   begin
      if not (Arg_Kind = A_Package_Declaration
              or else Arg_Kind = A_Generic_Package_Declaration
              or else Arg_Kind = A_Single_Protected_Declaration
              or else Arg_Kind = A_Protected_Type_Declaration)
      then
         return;
      end if;

      if State.New_List_Needed then
         --  No local body is needed for a given construct
         State.New_List_Needed := False;

      else
         --  We have to reset the current list:

         if State.Current_List /= null then
            State.Current_List := State.Current_List.Up;

            while State.Current_List.Prev /= null loop
               State.Current_List := State.Current_List.Prev;
            end loop;
         end if;
      end if;
   end Go_Up;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
   begin
      Create_Tree;

      Options.Initialized := True;
   exception
      when others =>
         Options.Initialized := False;
         raise;
   end Initialize;

   ----------
   -- Name --
   ----------

   function Name (Elem : in Asis.Element) return String is
      Def_Name : constant Asis.Element := Declarations.Names (Elem) (1);
   begin
      return Characters.Handling.To_String
        (Declarations.Defining_Name_Image (Def_Name));
   end Name;

   -----------
   -- Start --
   -----------

   procedure Start is

      use Text_IO;

      CU         : Asis.Compilation_Unit;
      CU_Kind    : Unit_Kinds;

      My_Control : Traverse_Control := Continue;
      My_State   : Body_State;

   begin
      Asis.Implementation.Initialize;

      Ada_Environments.Associate
        (My_Context,
        "My_Context",
        "-C1 " & Characters.Handling.To_Wide_String (Tree_Name.all));

      Ada_Environments.Open (My_Context);

      CU := Extensions.Main_Unit_In_Current_Tree (My_Context);

      CU_Kind := Compilation_Units.Unit_Kind (CU);

      if Compilation_Units.Is_Nil (CU) then
         Put_Line
           (Standard_Error,
            "Nothing to be done for " & To_String (Options.File_Name));
         return;

      else
         --  And here we have to do the job

         Create_Structure
           (Element => Elements.Unit_Declaration (CU),
            Control => My_Control,
            State   => My_State);

         if not Options.Quiet then
            New_Line;
         end if;

         Analyse_Structure;

         if not Options.Quiet then
            New_Line;
            Put_Line
              ("WSDL document " & To_String (Options.WSDL_File_Name)
                 & " is created for " & To_String (Options.File_Name) & '.');
         end if;
      end if;

      Ada_Environments.Close (My_Context);

      Ada_Environments.Dissociate (My_Context);

      Implementation.Finalize;

   exception

      when Ex : Asis.Exceptions.ASIS_Inappropriate_Context
             |  Asis.Exceptions.ASIS_Inappropriate_Container
             |  Asis.Exceptions.ASIS_Inappropriate_Compilation_Unit
             |  Asis.Exceptions.ASIS_Inappropriate_Element
             |  Asis.Exceptions.ASIS_Inappropriate_Line
             |  Asis.Exceptions.ASIS_Inappropriate_Line_Number
             |  Asis.Exceptions.ASIS_Failed
        =>
         New_Line (Standard_Error);

         Put_Line (Standard_Error, "Unexpected bug in Ada2WSDL v" & Version);
         Put      (Standard_Error, Exception_Name (Ex));
         Put_Line (Standard_Error, " raised");
         Put
           (Standard_Error, "ada2wsdl: ASIS Diagnosis is "
              & Characters.Handling.To_String (Asis.Implementation.Diagnosis));
         New_Line (Standard_Error);
         Put      (Standard_Error, "ada2wsdl: Status Value   is ");
         Put_Line (Standard_Error, Asis.Errors.Error_Kinds'Image
                   (Asis.Implementation.Status));
         Emergency_Clean_Up;
         raise Fatal_Error;

      when others =>
         Emergency_Clean_Up;
         raise;
   end Start;

end Ada2WSDL.Parser;
