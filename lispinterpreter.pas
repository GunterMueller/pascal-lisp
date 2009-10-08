unit LispInterpreter;

interface

uses
  LispTypes, LispSyntax;

type
  TLispInterpreter = class
  private
    FEnv: LV;

    function EvalApplication(Code, Env: LV; Tail: Boolean; var Proc, Args: LV): LV;
    function EvalExpr(Code, Env: LV; Tail: Boolean; var Proc, Args: LV): LV;
    function EvalCode(Code, Env: LV; Tail: Boolean; var Proc, Args: LV): LV;
    function LookupSymbol(Code, Env: LV): LV;       
    function ExpandArgs(Proc, Names, Values: LV): LV;
  public
    { The global environment }
    procedure RegisterGlobal(Name: string; P: LV);

    { Syntactic Extensions }
    //function Expand(Code, Env: LV): LV;

    { The main job of the interpreter }
    function Eval(Code: LV; Env: LV = nil): LV;
    function Apply(Proc, Args: LV): LV;

    { Some high-level stuff }
    function EvalString(S: string): LV;
    procedure REPL(Input, Output: LV);

    constructor Create(WithPrimitives: Boolean);
  end;


implementation

uses
  LispPrimitives;

{ TLispInterpreter }

function TLispInterpreter.EvalApplication(Code, Env: LV; Tail: Boolean; var Proc, Args: LV): LV;
var
  P, A, Cur: LV;
  Arg, Next: TLispPair;
begin
  P := Eval(LispCar(Code), Env);
  
  Cur := LispCdr(Code);
  if Cur = LispEmpty then
  begin
    A := LispEmpty;
  end
  else 
  begin
    Arg := TLispPair.Create(Eval(LispCar(Cur), Env), LispEmpty);
    Cur := LispCdr(Cur);
    A := Arg;
    while Cur <> LispEmpty do
    begin
      Next := TLispPair.Create(Eval(LispCar(Cur), Env), LispEmpty);
      Arg.D := Next;
      Arg := Next;
      Cur := LispCdr(Cur);
    end;
  end;

  if Tail then
  begin
    Proc := P;
    Args := A;
  end
  else
  begin
    Result := Apply(P, A);
  end;
end;

function TLispInterpreter.EvalExpr(Code, Env: LV; Tail: Boolean; var Proc, Args: LV): LV;
var
  ID: string;
  Tmp: LV;
begin
  if LispCar(Code) is TLispSymbol then
  begin
    ID := LispCar(Code).ToString;
    if ID = 'quote' then
    begin
      Result := LispCar(LispCdr(Code));
    end
    else if ID = 'if' then
    begin
      if Eval(LispRef(Code, 1), Env) = LispFalse then
      begin
        Result := EvalCode(LispRef(Code, 3), Env, Tail, Proc, Args);
      end
      else
      begin
        Result := EvalCode(LispRef(Code, 2), Env, Tail, Proc, Args);
      end;
    end
    else if ID = 'lambda' then
    begin
      Tmp := LispCdr(Code);
      Result := TLispClosure.Create('', LispCar(Tmp), LispCdr(Tmp), Env);
    end
    else if ID = 'set!' then
    begin
      Tmp := LookupSymbol(LispRef(Code, 1), Env);
      TLispPair(Tmp).D := Eval(LispRef(Code, 2), Env);
      Result := LispVoid;
    end
    else
    begin
      Result := EvalApplication(Code, Env, Tail, Proc, Args);
    end
  end
  else
  begin
    Result := EvalApplication(Code, Env, Tail, Proc, Args);
  end;
end;

function TLispInterpreter.EvalCode(Code, Env: LV; Tail: Boolean; var Proc, Args: LV): LV;
begin
  if Env = nil then
  begin
    Env := FEnv;
  end;

  if Code is TLispPair then
  begin  
    Result := EvalExpr(Code, Env, Tail, Proc, Args);
  end
  else if Code is TLispSymbol then
  begin
    Result := LispCdr(LookupSymbol(Code, Env));
  end
  else
  begin
    Result := Code;
  end;
end;

function TLispInterpreter.LookupSymbol(Code, Env: LV): LV;
var
  Cur, Binding: LV;
  Name, BindName: TLispSymbol;
begin
  Name := TLispSymbol(Code);
  Cur := Env;

  while Cur <> LispEmpty do
  begin
    Binding := LispCar(Cur);
    BindName := TLispSymbol(LispCar(Binding));
    LispTypeCheck(BindName, TLispSymbol, 'Invalid binding name');
        
    if Name.Ident = BindName.Ident then
    begin
      Result := Binding;
      exit;
    end;

    Cur := LispCdr(Cur);
  end;

  raise ELispError.Create('Unknown variable', Code);
end;

function TLispInterpreter.ExpandArgs(Proc, Names, Values: LV): LV;
var
  Head: LV;
begin
  if (Names = LispEmpty) and (Values <> LispEmpty) then
  begin
    raise ELispError.Create('Too many arguments', Proc);
  end;

  if Names = LispEmpty then
  begin
    Result := LispEmpty;
  end
  else if Names is TLispPair then
  begin
    if Values = LispEmpty then
    begin
      raise ELispError.Create('Not enough arguments', Proc);
    end;

    Head := TLispPair.Create(LispCar(Names), LispCar(Values));
    Result := TLispPair.Create(Head, ExpandArgs(Proc, LispCdr(Names), LispCdr(Values)));
  end
  else
  begin
    Result := TLispPair.Create(TLispPair.Create(Names, Values), LispEmpty);
  end;
end;

procedure TLispInterpreter.RegisterGlobal(Name: string; P: LV);
var
  Binding: LV;
begin
  Binding := TLispPair.Create(TLispSymbol.Create(Name), P);
  FEnv := TLispPair.Create(Binding, FEnv);
end;

function TLispInterpreter.Eval(Code, Env: LV): LV;
var
  DummyProc, DummyArgs: LV;
begin
  Result := EvalCode(Code, Env, False, DummyProc, DummyArgs);
end;

function TLispInterpreter.Apply(Proc, Args: LV): LV;
var
  Closure: TLispClosure;
  Cur, Env: LV;
begin
  repeat
    if Proc is TLispPrimitive then
    begin
      Result := TLispPrimitive(Proc).Exec(Args);
      Proc := nil;
    end
    else if Proc is TLispClosure then
    begin
      Closure := TLispClosure(Proc);
      Env := LispAppend(ExpandArgs(Proc, Closure.Args, Args), Closure.Env);
      Proc := nil;
      Cur := Closure.Code;
      Result := LispVoid;
      while Cur <> LispEmpty do
      begin
        if LispCdr(Cur) = LispEmpty then
        begin
          Result := EvalCode(LispCar(Cur), Env, True, Proc, Args);       
        end 
        else
        begin
          Result := Eval(LispCar(Cur), Env);
        end;
        Cur := LispCdr(Cur);
      end;
    end
    else
    begin
      raise ELispError.Create('Not a procedure', Proc);
    end;
  until Proc = nil;
end;

function TLispInterpreter.EvalString(S: string): LV;
begin
  Result := Eval(LispReadString(S));
end;

procedure TLispInterpreter.REPL(Input, Output: LV);
var
  Result: LV;
begin
  while not LispEOF(Input) do
  begin
    try
      Result := Eval(LispRead(Input));
      if Result <> LispEOFObject then
      begin
        LispWrite(Result, Output);
        LispWriteChar(#10, Output);
      end;
    except
      on E: ELispError do
      begin
        LispWriteString(E.Message, Output);
        LispWriteChar(#10, Output);
      end;
    end;
  end;
end;

constructor TLispInterpreter.Create(WithPrimitives: Boolean);
begin
  FEnv := LispEmpty;
  if WithPrimitives then
  begin
    RegisterPrimitives(Self);
  end;
end;

end.