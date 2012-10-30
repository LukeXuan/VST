Require Export veric.base.
Require Export veric.Address.
Require Import msl.rmaps.
Require Import msl.rmaps_lemmas.
Require Import veric.compcert_rmaps.
Require Import veric.slice.
Require Import veric.res_predicates.
Require Import veric.expr.

(* THESE NEXT DEFINITIONS are inconvenient to have inside the proof
  of separation logic soundness, but are necessary to have for the 
  client of the separation logic who wants to import the separation
   logic opaquely. *)
Definition rmap := rmap.
Instance Join_rmap: Join rmap := _.
Instance Perm_rmap: @Perm_alg rmap Join_rmap := _.
Instance Sep_rmap: @Sep_alg rmap Join_rmap := _.
Instance Canc_rmap: @Canc_alg rmap Join_rmap := _.
Instance Disj_rmap: @Disj_alg rmap Join_rmap := _.
Instance ag_rmap: ageable rmap := _.
Instance Age_rmap: @Age_alg rmap Join_rmap ag_rmap := _.
Instance Cross_rmap: Cross_alg rmap := _.
Instance Trip_rmap: Trip_alg rmap := _.

(* an experiment ... 
Instance Join_environ : Join environ := Join_equiv _.
Instance Perm_environ : Perm_alg environ := _.
Instance Sep_environ : Sep_alg environ := _.
Instance Canc_environ: Canc_alg environ := _.
Instance Disj_environ: Disj_alg environ := _.

Instance ag_environ_rmap : ageable (environ * rmap) := ag_prod' environ rmap _.
Instance Age_environ_rmap : Age_alg (environ * rmap) := asa_prod' _ _ _ _ _ _.
*)
Definition core_load : memory_chunk -> address -> val -> pred rmap := core_load.

Definition VALspec_range: Z -> Share.t -> Share.t -> address -> pred rmap := VALspec_range.

Definition address_mapsto: memory_chunk -> val -> Share.t -> Share.t -> address -> pred rmap := 
       address_mapsto.

Lemma address_mapsto_exists:
  forall ch v rsh (sh: pshare) loc w0
      (RESERVE: forall l', adr_range loc (size_chunk ch) l' -> w0 @ l' = NO Share.bot),
      (align_chunk ch | snd loc) ->
      exists w, address_mapsto ch (decode_val ch (encode_val ch v)) rsh (pshare_sh sh) loc w 
                    /\ core w = core w0.
Proof.  exact address_mapsto_exists. Qed.

Lemma address_mapsto_VALspec_range: 
  forall (ch : memory_chunk) (v : val) rsh (sh : Share.t) (l : address),
       address_mapsto ch v rsh sh l
       |-- VALspec_range (size_chunk ch) rsh sh l.
Proof.  exact address_mapsto_VALspec_range. Qed.

Open Local Scope pred.


Definition func_at (f: funspec): address -> pred rmap :=
  match f with
   | mk_funspec fsig A P Q => pureat (SomeP (A::boolT::environ::nil) (packPQ P Q)) (FUN fsig)
  end.


Definition assert: Type := environ -> pred rmap.

Bind Scope pred with assert.
Local Open Scope pred.

Definition closed_wrt_vars {B} (S: ident -> Prop) (F: environ -> B) : Prop := 
  forall rho te',  
     (forall i, S i \/ Map.get (te_of rho) i = Map.get te' i) ->
     F rho = F (mkEnviron (ge_of rho) (ve_of rho) te').

(*Definition expr_true (e: Clight.expr) (rho: environ): Prop := 
  bool_val (eval_expr e rho) (Clight.typeof e) = Some true.*)

Definition typed_true (t: type) (v: val)  : Prop := strict_bool_val v t
= Some true.

Definition typed_false (t: type)(v: val) : Prop := strict_bool_val v t =
Some false.

Definition expr_true e := lift1 (typed_true (typeof e)) (eval_expr e).

Definition expr_false e := lift1 (typed_false (typeof e)) (eval_expr e).

Definition subst {A} (x: ident) (v: val) (P: environ -> A) : environ -> A :=
   fun s => P (env_set s x v).


Definition mapsto (sh: Share.t) (t: type) (v1 v2 : val): pred rmap :=
  match access_mode t with
  | By_value ch => 
    match v1 with
     | Vptr b ofs => 
          address_mapsto ch v2 (Share.unrel Share.Lsh sh) (Share.unrel Share.Rsh sh) (b, Int.unsigned ofs)
     | _ => FF
    end
  | _ => FF
  end. 

Definition writable_block (id: ident) (n: Z): assert :=
   fun rho => 
        EX v: val*type,  EX a: address, EX rsh: Share.t,
          !! (ge_of rho id = Some v /\ val2adr (fst v) a) && VALspec_range n rsh Share.top a.

Fixpoint writable_blocks (bl : list (ident*Z)) : assert :=
 match bl with
  | nil =>  fun rho => emp 
  | (b,n)::bl' =>  fun rho => writable_block b n rho * writable_blocks bl' rho
 end.

Definition fun_assert: 
  forall (fml: funsig) (A: Type) (P Q: A -> environ -> pred rmap)  (v: val) , pred rmap :=
  res_predicates.fun_assert.

Definition lvalue_block (rsh: Share.t) (e: Clight.expr) : assert :=
  fun rho => 
     match eval_lvalue e rho with 
     | Vptr b i => VALspec_range (sizeof (Clight.typeof e)) rsh Share.top (b, Int.unsigned i)
     | _ => FF
    end.

Definition var_block (rsh: Share.t) (idt: ident * type) : assert :=
         lvalue_block rsh (Clight.Evar (fst idt) (snd idt)).

Fixpoint sepcon_list {A}{JA: Join A}{PA: Perm_alg A}{SA: Sep_alg A}{AG: ageable A} {AgeA: Age_alg A}
   (p: list (pred A)) : pred A :=
 match p with nil => emp | h::t => h * sepcon_list t end.


Definition stackframe_of (f: Clight.function) : assert :=
  fold_right (fun P Q rho => P rho * Q rho) (fun rho => emp) (map (fun idt => var_block Share.top idt) (Clight.fn_vars f)).

Lemma stackframe_of_eq : stackframe_of = 
        fun f rho => fold_right sepcon emp (map (fun idt => var_block Share.top idt rho) (Clight.fn_vars f)).
Proof.
 extensionality f rho.
 unfold stackframe_of.
 forget (fn_vars f) as vl.
 induction vl; simpl; auto.
 rewrite IHvl; auto.
Qed.

(*
Definition stackframe_of (f: Clight.function) : assert :=
  fun rho => sepcon_list (map (fun idt => var_block Share.top idt rho) (Clight.fn_vars f)).
*)

Lemma  subst_extens: 
 forall a v P Q, (forall rho, P rho |-- Q rho) -> forall rho, subst a v P rho |-- subst a v Q rho.
Proof.
unfold subst, derives.
simpl;
auto.
Qed.

Definition tc_formals (formals: list (ident * type)) : environ -> Prop :=
     fun rho => typecheck_vals (map (fun xt => (eval_id (fst xt) rho)) formals) (map (@snd _ _) formals) = true.

Definition bind_args (formals: list (ident * type)) (P: environ -> pred rmap) : assert :=
          fun rho => !! tc_formals formals rho && P rho.

Definition globals_only (rho: environ) : environ := (mkEnviron (ge_of rho) (Map.empty _) (Map.empty _)).

Definition ret_temp : ident := 1%positive.

Fixpoint make_args (il: list ident) (vl: list val) (rho: environ)  :=
  match il, vl with 
  | nil, nil => globals_only rho
  | i::il', v::vl' => env_set (make_args il' vl' rho) i v
   | _ , _ => rho 
 end.

Definition get_result1 (ret: ident) (rho: environ) : environ :=
   make_args (ret_temp::nil) (eval_id ret rho :: nil) rho.

Definition get_result (ret: option ident) : environ -> environ :=
 match ret with 
 | None => make_args nil nil
 | Some x => get_result1 x
 end.

Definition bind_ret (vl: list val) (t: type) (Q: assert) : assert :=
     match vl, t with
     | nil, Tvoid => fun rho => Q (make_args nil nil rho)
     | v::nil, _ => fun rho => !! (typecheck_val v t = true) && 
                               Q (make_args (ret_temp::nil) (v::nil) rho)
     | _, _ => fun rho => FF
     end.

Definition funassert (Delta: tycontext): assert := 
 fun rho => 
   (ALL  id: ident, ALL fs:funspec,  !! ((glob_types Delta)!id = Some (Global_func fs)) -->
              EX v:val, EX loc:address, 
                   !! (ge_of rho id = Some (v, type_of_funspec fs)
                                 /\ val2adr v loc) && func_at fs loc)
   && 
   (ALL  loc: address, ALL fs:funspec, func_at fs loc --> 
             EX id:ident,EX v:val,  !! (ge_of rho id = Some (v, type_of_funspec fs)
                                 /\ val2adr v loc) 
               && !! exists fs, (glob_types Delta)!id = Some (Global_func fs)).

(* Unfortunately, we need core_load in the interface as well as address_mapsto,
  because the converse of 'mapsto_core_load' lemma is not true.  The reason is
  that core_load could imply partial ownership of the four bytes of the word
  using different shares that don't have a common core, whereas address_mapsto
  requires the same share on all four bytes. *)

Definition ret_assert := exitkind -> list val -> assert.

Definition overridePost  (Q: assert)  (R: ret_assert) := 
     fun ek vl => if eq_dec ek EK_normal then (fun rho => !! (vl=nil) && Q rho) else R ek vl.

Definition existential_ret_assert {A: Type} (R: A -> ret_assert) := 
  fun ek vl rho => EX x:A, R x ek vl rho.

Definition normal_ret_assert (Q: assert) : ret_assert := 
   fun ek vl rho => !!(ek = EK_normal) && (!! (vl = nil) && Q rho).

Definition with_ge (ge: genviron) (G: assert) : pred rmap :=
     G (mkEnviron ge (Map.empty _) (Map.empty _)).

Definition frame_ret_assert (R: ret_assert) (F: assert) : ret_assert := 
      fun ek vl rho => R ek vl rho * F rho.

Require Import msl.normalize.

Lemma normal_ret_assert_derives:
 forall P Q rho,
  P rho |-- Q rho ->
  forall ek vl, normal_ret_assert P ek vl rho |-- normal_ret_assert Q ek vl rho.
Proof.
 intros.
 unfold normal_ret_assert; intros; normalize.
Qed.
Hint Resolve normal_ret_assert_derives.

Lemma normal_ret_assert_FF:
  forall ek vl rho, normal_ret_assert (fun rho => FF) ek vl rho = FF.
Proof.
unfold normal_ret_assert. intros. normalize.
Qed.

Lemma frame_normal:
  forall P F, 
   frame_ret_assert (normal_ret_assert P) F = normal_ret_assert (fun rho => P rho * F rho).
Proof.
intros.
extensionality ek vl rho.
unfold frame_ret_assert, normal_ret_assert.
normalize.
Qed.

Definition for1_ret_assert (Inv: assert) (R: ret_assert) : ret_assert :=
 fun ek vl =>
 match ek with
 | EK_normal => Inv
 | EK_break => R EK_normal nil
 | EK_continue => Inv
 | EK_return => R EK_return vl
 end.

Definition for2_ret_assert (Inv: assert) (R: ret_assert) : ret_assert :=
 fun ek vl =>
 match ek with
 | EK_normal => Inv
 | EK_break => fun _ => FF
 | EK_continue => fun _ => FF 
 | EK_return => R EK_return vl
 end.

Lemma frame_for1:
  forall Q R F, 
   frame_ret_assert (for1_ret_assert Q R) F = 
   for1_ret_assert (fun rho => Q rho * F rho) (frame_ret_assert R F).
Proof.
intros.
extensionality ek vl rho.
unfold frame_ret_assert, for1_ret_assert.
destruct ek; normalize.
Qed.

Lemma frame_for2:
  forall Q R F, 
   frame_ret_assert (for2_ret_assert Q R) F = 
   for2_ret_assert (fun rho => Q rho * F rho) (frame_ret_assert R F).
Proof.
intros.
extensionality ek vl rho.
unfold frame_ret_assert, for2_ret_assert.
destruct ek; normalize.
Qed.

Lemma overridePost_normal:
  forall P Q, overridePost P (normal_ret_assert Q) = normal_ret_assert P.
Proof.
intros; unfold overridePost, normal_ret_assert.
extensionality ek vl rho.
if_tac; normalize.
subst ek.
apply pred_ext; normalize.
apply pred_ext; normalize.
Qed.

Hint Rewrite normal_ret_assert_FF frame_normal frame_for1 frame_for2 
                 overridePost_normal: normalize.

Definition function_body_ret_assert (ret: type) (Q: assert) : ret_assert := 
   fun (ek : exitkind) (vl : list val) =>
     match ek with
     | EK_return => bind_ret vl ret Q 
     | _ => fun rho => FF
     end.

Definition tc_expr (Delta: tycontext) (e: expr) : assert:= 
  fun rho => !! denote_tc_assert (typecheck_expr Delta e) rho.

Definition tc_exprlist (Delta: tycontext) (e: list expr) : assert := 
      fun rho => !! denote_tc_assert (typecheck_exprlist Delta e) rho.

Definition tc_lvalue (Delta: tycontext) (e: expr) : assert := 
     fun rho => !! denote_tc_assert (typecheck_lvalue Delta e) rho.

Lemma extend_tc_expr: forall Delta e rho, boxy extendM (tc_expr Delta e rho).
Admitted.
Lemma extend_tc_exprlist: forall Delta e rho, boxy extendM (tc_exprlist Delta e rho).
Admitted.
Lemma extend_tc_lvalue: forall Delta e rho, boxy extendM (tc_lvalue Delta e rho).
Admitted.
Hint Resolve extend_tc_expr extend_tc_exprlist extend_tc_lvalue.
Hint Resolve (@extendM_refl rmap _ _ _ _ _).

Definition writable_share (sh: share) := join_sub (Share.rel Share.Rsh Share.top) sh.
Lemma writable_share_right: forall sh, writable_share sh -> Share.unrel Share.Rsh sh = Share.top.
Admitted.




