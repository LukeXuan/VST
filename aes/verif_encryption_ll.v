Require Import floyd.proofauto.
Require Import aes.aes.
Require Import aes.tablesLL.

Instance CompSpecs : compspecs.
Proof. make_compspecs prog. Defined.
Definition Vprog : varspecs.  mk_varspecs prog. Defined.

(* definitions copied from other files, just to see what we need: *)
Definition t_struct_aesctx := Tstruct _mbedtls_aes_context_struct noattr.
Definition t_struct_tables := Tstruct _aes_tables_struct noattr.
Definition Nr := 14. (* number of cipher rounds *)

Definition tables_initialized (tables : val) := data_at Ews t_struct_tables 
  (map Vint FSb, (map Vint FT0, (map Vint FT1, (map Vint FT2, (map Vint FT3,
  (map Vint RSb, (map Vint RT0, (map Vint RT1, (map Vint RT2, (map Vint RT3, 
  (map Vint RCON))))))))))) tables.

(* arr: list of 4 bytes *)
Definition get_uint32_le (arr: list Z) (i: Z) : int :=
 (Int.or (Int.or (Int.or
            (Int.repr (Znth  i    arr 0))
   (Int.shl (Int.repr (Znth (i+1) arr 0)) (Int.repr  8)))
   (Int.shl (Int.repr (Znth (i+2) arr 0)) (Int.repr 16)))
   (Int.shl (Int.repr (Znth (i+3) arr 0)) (Int.repr 24))).

(* outputs a list of 4 bytes *)
Definition put_uint32_le (x : int) : list int :=
  [ (Int.and           x                (Int.repr 255));
    (Int.and (Int.shru x (Int.repr  8)) (Int.repr 255));
    (Int.and (Int.shru x (Int.repr 16)) (Int.repr 255));
    (Int.and (Int.shru x (Int.repr 24)) (Int.repr 255)) ].

Definition byte0 (x : int) : Z :=
  (Z.land (Int.unsigned x) (Int.unsigned (Int.repr 255))).
Definition byte1 (x : int) : Z :=
  (Z.land (Int.unsigned (Int.shru x (Int.repr 8))) (Int.unsigned (Int.repr 255))).
Definition byte2 (x : int) : Z :=
  (Z.land (Int.unsigned (Int.shru x (Int.repr 16))) (Int.unsigned (Int.repr 255))).
Definition byte3 (x : int) : Z :=
  (Z.land (Int.unsigned (Int.shru x (Int.repr 24))) (Int.unsigned (Int.repr 255))).

Definition mbed_tls_fround_col (col0 col1 col2 col3 : int) (rk : int) : int :=
  (Int.xor (Int.xor (Int.xor (Int.xor rk
    (Znth (byte0 col0) FT0 Int.zero))
    (Znth (byte1 col1) FT1 Int.zero))
    (Znth (byte2 col2) FT2 Int.zero))
    (Znth (byte3 col3) FT3 Int.zero)).

Definition four_ints := (int * (int * (int * int)))%type.

Definition mbed_tls_fround (cols : four_ints) (rks : list int) (i : Z) : four_ints :=
match cols with (col0, (col1, (col2, col3))) =>
  ((mbed_tls_fround_col col0 col1 col2 col3 (Znth  i    rks Int.zero)),
  ((mbed_tls_fround_col col1 col2 col3 col0 (Znth (i+1) rks Int.zero)),
  ((mbed_tls_fround_col col2 col3 col0 col1 (Znth (i+2) rks Int.zero)),
   (mbed_tls_fround_col col3 col0 col1 col2 (Znth (i+3) rks Int.zero)))))
end.

Fixpoint mbed_tls_enc_rounds (n : nat) (state : four_ints) (rks : list int) (i : Z) : four_ints :=
match n with
| O => state
| S m => mbed_tls_enc_rounds m (mbed_tls_fround state rks i) rks (i+4)
end.

Definition mbed_tls_final_enc_round (state : four_ints) (rks : list int) : four_ints := state. (* TODO *)

(* plaintext: array of bytes
   rks: expanded round keys, array of Int32 *)
Definition mbed_tls_initial_add_round_key (plaintext : list Z) (rks : list int) : four_ints :=
((Int.xor (get_uint32_le plaintext  0) (Znth 0 rks Int.zero)),
((Int.xor (get_uint32_le plaintext  4) (Znth 1 rks Int.zero)),
((Int.xor (get_uint32_le plaintext  8) (Znth 2 rks Int.zero)),
 (Int.xor (get_uint32_le plaintext 12) (Znth 3 rks Int.zero))))).

Definition mbed_tls_aes_enc (plaintext : list Z) (rks : list int) : list int :=
  let state0 := mbed_tls_initial_add_round_key plaintext rks in
  match (mbed_tls_final_enc_round (mbed_tls_enc_rounds 13 state0 rks 0) rks) with
  | (col0, (col1, (col2, col3))) => 
       (put_uint32_le col0) ++ (put_uint32_le col1) ++ (put_uint32_le col2) ++ (put_uint32_le col3)
  end.

Definition encryption_spec_ll :=
  DECLARE _mbedtls_aes_encrypt
  WITH ctx : val, input : val, output : val, (* arguments *)
       ctx_sh : share, in_sh : share, out_sh : share, (* shares *)
       plaintext : list Z, (* 16 chars *)
       exp_key : list Z, (* expanded key, 4*(Nr+1)=60 32-bit integers *)
       tables : val (* global var *)
  PRE [ _ctx OF (tptr t_struct_aesctx), _input OF (tptr tuchar), _output OF (tptr tuchar) ]
    PROP (Zlength plaintext = 16; Zlength exp_key = 60;
          readable_share ctx_sh; readable_share in_sh; writable_share out_sh)
    LOCAL (temp _ctx ctx; temp _input input; temp _output output; gvar _tables tables)
    SEP (data_at ctx_sh (t_struct_aesctx) (
          (Vint (Int.repr Nr)), 
          ((field_address t_struct_aesctx [StructField _buf] ctx),
          (map Vint (map Int.repr (exp_key ++ (list_repeat (8%nat) 0)))))
          (* The following weaker precondition would also be provable, but less conveniently, and   *)
          (* since mbedtls_aes_init zeroes the whole buffer, we exploit this to simplify the proof  *)
          (* ((map Vint (map Int.repr exp_key)) ++ (list_repeat (8%nat) Vundef))) *)
         ) ctx;
         data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
         data_at_ out_sh (tarray tuchar 16) output;
         tables_initialized tables)
  POST [ tvoid ]
    PROP() LOCAL()
    SEP (data_at out_sh (tarray tuchar 16) 
                        (map Vint (mbed_tls_aes_enc plaintext (map Int.repr exp_key)))
                         output).

(* QQQ: How to know that if x is stored in a var of type tuchar, 0 <= x < 256 ? *)
(* QQQ: Declare vars of type Z or of type int in API spec ? *)

Definition Gprog : funspecs := ltac:(with_library prog [ encryption_spec_ll ]).

Ltac simpl_Int := repeat match goal with
| |- context [ (Int.mul (Int.repr ?A) (Int.repr ?B)) ] =>
    let x := fresh "x" in (pose (x := (A * B)%Z)); simpl in x;
    replace (Int.mul (Int.repr A) (Int.repr B)) with (Int.repr x); subst x; [|reflexivity]
| |- context [ (Int.add (Int.repr ?A) (Int.repr ?B)) ] =>
    let x := fresh "x" in (pose (x := (A + B)%Z)); simpl in x;
    replace (Int.add (Int.repr A) (Int.repr B)) with (Int.repr x); subst x; [|reflexivity]
end.

Lemma masked_byte_range: forall i,
  0 <= Z.land i 255 < 256. Admitted.

Lemma body_aes_encrypt: semax_body Vprog Gprog f_mbedtls_aes_encrypt encryption_spec_ll.
Proof.
  start_function.
  (* TODO floyd: put (Sreturn None) in such a way that the code can be folded into MORE_COMMANDS *)

  (* RK = ctx->rk; *)
  forward.
  { entailer!. auto with field_compatible. (* TODO floyd: why is this not done automatically? *) }

  assert_PROP (field_compatible t_struct_aesctx [StructField _buf] ctx) as Fctx. entailer!.
  assert ((field_address t_struct_aesctx [StructField _buf] ctx)
        = (field_address t_struct_aesctx [ArraySubsc 0; StructField _buf] ctx)) as Eq. {
    do 2 rewrite field_compatible_field_address by auto with field_compatible.
    reflexivity.
  }
  rewrite Eq in *. clear Eq.
  remember (exp_key ++ list_repeat 8 0) as buf.
  (* TODO floyd: This is important for automatic rewriting of (Znth (map Vint ...)), and if
     it's not done, the tactics might become very slow, especially if they try to simplify complex
     terms that they would never attempt to simplify if the rewriting had succeeded.
     How should the user be told to put prove such assertions before continuing? *)
  assert (Zlength buf = 68) as LenBuf. {
    subst. rewrite Zlength_app. rewrite H0. reflexivity.
  }

  Ltac forward2 :=
    (forward; autorewrite with sublist); (* TODO floyd why doesn't entailer do the autorewrite? *)
    [ solve [ entailer! ] | idtac ].

  (* GET_UINT32_LE( X0, input,  0 ); X0 ^= *RK++;
     GET_UINT32_LE( X1, input,  4 ); X1 ^= *RK++;
     GET_UINT32_LE( X2, input,  8 ); X2 ^= *RK++;
     GET_UINT32_LE( X3, input, 12 ); X3 ^= *RK++; *)
  Ltac GET_UINT32_LE_tac := do 4 forward2.

  assert_PROP (forall i, 0 <= i < 60 -> force_val (sem_add_pi tuint
       (field_address t_struct_aesctx [ArraySubsc  i   ; StructField _buf] ctx) (Vint (Int.repr 1)))
     = (field_address t_struct_aesctx [ArraySubsc (i+1); StructField _buf] ctx)) as Eq. {
    entailer!. intros.
    do 2 rewrite field_compatible_field_address by auto with field_compatible.
    simpl. destruct ctx; inversion PNctx; try reflexivity.
    simpl. rewrite Int.add_assoc.
    replace (Int.mul (Int.repr 4) (Int.repr 1)) with (Int.repr 4) by reflexivity.
    rewrite add_repr.
    replace (8 + 4 * (i + 1)) with (8 + 4 * i + 4) by omega.
    reflexivity.
  }

  Time do 4 (
    GET_UINT32_LE_tac; simpl; forward; forward; forward;
    rewrite Eq by omega; simpl;
    forward2; forward
  ). (* 556s *)

  do 4 match goal with
  | |- context [temp _ (Vint (Int.xor ?E (Int.repr (Znth ?i buf 0))))] =>
    let i4 := eval simpl in (4 * i)%Z in
    progress change E with (get_uint32_le plaintext i4)
  end.

unfold Sfor.

(* beginning of for loop *)

forward. forward.

(* ugly hack to avoid type mismatch between
   "(val * (val * list val))%type" and "reptype t_struct_aesctx" *)
assert (exists (v: reptype t_struct_aesctx), v =
       (Vint (Int.repr Nr),
          (field_address t_struct_aesctx [ArraySubsc 0; StructField _buf] ctx,
          map Vint (map Int.repr buf))))
as EE by (eexists; reflexivity).

destruct EE as [vv EE].

eapply semax_seq' with (P' :=
  PROP ( )
  LOCAL (
     temp _RK (field_address t_struct_aesctx [ArraySubsc 4; StructField _buf] ctx);
     temp _X3 (Vint (Int.xor (get_uint32_le plaintext 12) (Int.repr (Znth 3 buf 0))));
     temp _X2 (Vint (Int.xor (get_uint32_le plaintext 8) (Int.repr (Znth 2 buf 0))));
     temp _X1 (Vint (Int.xor (get_uint32_le plaintext 4) (Int.repr (Znth 1 buf 0))));
     temp _X0 (Vint (Int.xor (get_uint32_le plaintext 0) (Int.repr (Znth 0 buf 0))));
     temp _ctx ctx;
     temp _input input;
     temp _output output;
     gvar _tables tables
  ) SEP (
     data_at_ out_sh (tarray tuchar 16) output;
     tables_initialized tables;
     data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
     data_at ctx_sh t_struct_aesctx vv ctx 
  )
).
{
apply semax_pre with (P' := 
  (EX i: Z,   PROP ( ) LOCAL (
     temp _i (Vint (Int.repr i));
     temp _RK (field_address t_struct_aesctx [ArraySubsc 4; StructField _buf] ctx);
     temp _X3 (Vint (Int.xor (get_uint32_le plaintext 12) (Int.repr (Znth 3 buf 0))));
     temp _X2 (Vint (Int.xor (get_uint32_le plaintext 8) (Int.repr (Znth 2 buf 0))));
     temp _X1 (Vint (Int.xor (get_uint32_le plaintext 4) (Int.repr (Znth 1 buf 0))));
     temp _X0 (Vint (Int.xor (get_uint32_le plaintext 0) (Int.repr (Znth 0 buf 0))));
     temp _ctx ctx;
     temp _input input;
     temp _output output;
     gvar _tables tables
  ) SEP (
     data_at_ out_sh (tarray tuchar 16) output;
     tables_initialized tables;
     data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
     data_at ctx_sh t_struct_aesctx vv ctx 
  ))).
{ subst vv. Exists 6. entailer!. }
{ apply semax_loop with (
  (EX i: Z,   PROP ( ) LOCAL ( 
     temp _i (Vint (Int.repr i));
     temp _RK (field_address t_struct_aesctx [ArraySubsc 4; StructField _buf] ctx);
     temp _X3 (Vint (Int.xor (get_uint32_le plaintext 12) (Int.repr (Znth 3 buf 0))));
     temp _X2 (Vint (Int.xor (get_uint32_le plaintext 8) (Int.repr (Znth 2 buf 0))));
     temp _X1 (Vint (Int.xor (get_uint32_le plaintext 4) (Int.repr (Znth 1 buf 0))));
     temp _X0 (Vint (Int.xor (get_uint32_le plaintext 0) (Int.repr (Znth 0 buf 0))));
     temp _ctx ctx;
     temp _input input;
     temp _output output;
     gvar _tables tables
  ) SEP (
     data_at_ out_sh (tarray tuchar 16) output;
     tables_initialized tables;
     data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
     data_at ctx_sh t_struct_aesctx vv ctx 
  ))).
{ (* loop body *) 
Intro i.

forward_if (PROP ( ) LOCAL (
     temp _i (Vint (Int.repr i));
     temp _RK (field_address t_struct_aesctx [ArraySubsc 4; StructField _buf] ctx);
     temp _X3 (Vint (Int.xor (get_uint32_le plaintext 12) (Int.repr (Znth 3 buf 0))));
     temp _X2 (Vint (Int.xor (get_uint32_le plaintext 8) (Int.repr (Znth 2 buf 0))));
     temp _X1 (Vint (Int.xor (get_uint32_le plaintext 4) (Int.repr (Znth 1 buf 0))));
     temp _X0 (Vint (Int.xor (get_uint32_le plaintext 0) (Int.repr (Znth 0 buf 0))));
     temp _ctx ctx;
     temp _input input;
     temp _output output;
     gvar _tables tables
  ) SEP (
     data_at_ out_sh (tarray tuchar 16) output;
     tables_initialized tables;
     data_at in_sh (tarray tuchar 16) (map Vint (map Int.repr plaintext)) input;
     data_at ctx_sh t_struct_aesctx vv ctx
  )).
{ (* then-branch: Sskip to body *)
  forward. entailer!.
 }
{
 (* else-branch: exit loop *)
  forward. entailer!.
 }
{ (* rest: loop body *)
  unfold tables_initialized. subst vv.

Ltac remember_temp_Vints done :=
  lazymatch goal with
  | |- context [ ?T :: done ] => match T with
    | temp ?Id (Vint ?V) =>
      let V0 := fresh "V" in remember V as V0;
      remember_temp_Vints ((temp Id (Vint V0)) :: done)
    | _ => remember_temp_Vints (T :: done)
    end
  | |- semax _ (PROPx _ (LOCALx done (SEPx _))) _ _ => idtac
  | _ => fail 100 "assertion failure: did not find" done
  end.

Ltac entailer_for_load_tac ::=
  rewrite ?Znth_map with (d' := Int.zero) by apply masked_byte_range;
  try quick_typecheck3.

  forward. forward. rewrite Eq by omega. simpl.
  forward2.
  do 4 (forward; [apply prop_right; apply masked_byte_range | ]).
  rewrite ?Znth_map with (d' := Int.zero) by apply masked_byte_range.
  remember_temp_Vints (@nil localdef).
  forward.

  forward. forward. rewrite Eq by omega. simpl.
  forward2.
  do 4 (forward; [apply prop_right; apply masked_byte_range | ]).
  rewrite ?Znth_map with (d' := Int.zero) by apply masked_byte_range.
  remember_temp_Vints (@nil localdef).
  forward.

  forward. forward. rewrite Eq by omega. simpl.
  forward2.
  do 4 (forward; [apply prop_right; apply masked_byte_range | ]).
  rewrite ?Znth_map with (d' := Int.zero) by apply masked_byte_range.
  remember_temp_Vints (@nil localdef).
  forward.

  forward. forward. rewrite Eq by omega. simpl.
  forward2.
  do 4 (forward; [apply prop_right; apply masked_byte_range | ]).
  rewrite ?Znth_map with (d' := Int.zero) by apply masked_byte_range.
  remember_temp_Vints (@nil localdef).
  forward.

  repeat subst.

  match goal with
  | |- context [ Z.land (Int.unsigned (Int.shru ?x (Int.repr 24))) (Int.unsigned (Int.repr 255)) ] =>
    change (Z.land (Int.unsigned (Int.shru ?x (Int.repr 24))) (Int.unsigned (Int.repr 255)))
    with (byte3 x)
  end.
  match goal with
  | |- context [ Z.land (Int.unsigned (Int.shru ?x (Int.repr 16))) (Int.unsigned (Int.repr 255)) ] =>
    change (Z.land (Int.unsigned (Int.shru ?x (Int.repr 16))) (Int.unsigned (Int.repr 255)))
    with (byte2 x)
  end.
  match goal with
  | |- context [ Z.land (Int.unsigned (Int.shru ?x (Int.repr 8))) (Int.unsigned (Int.repr 255)) ] =>
    change (Z.land (Int.unsigned (Int.shru ?x (Int.repr 8))) (Int.unsigned (Int.repr 255)))
    with (byte1 x)
  end.
  do 4 match goal with
  | |- context [ Z.land (Int.unsigned ?x) (Int.unsigned (Int.repr 255)) ] =>
    change (Z.land (Int.unsigned x) (Int.unsigned (Int.repr 255))) with (byte0 x)
  end.

Definition mbed_tls_fround_colCORRECT (col0 col1 col2 col3 : int) (rk : Z) : int :=
  (Int.xor (Int.xor (Int.xor (Int.xor (Int.repr rk)
    (Znth (byte0 col0) FT0 Int.zero))
    (Znth (byte1 col1) FT1 Int.zero))
    (Znth (byte2 col2) FT2 Int.zero))
    (Znth (byte3 col3) FT3 Int.zero)).

  do 4 match goal with
  | |- context [ temp _ (Vint ?E) ] =>
    evar (col0: int); evar (col1: int); evar (col2: int); evar (col3: int); evar (rk: Z); 
    assert (E = mbed_tls_fround_colCORRECT col0 col1 col2 col3 rk) as EqY;
    subst col0 col1 col2 col3 rk; [reflexivity | progress rewrite EqY; clear EqY]
  end.

Definition mbed_tls_initial_add_round_key_col (col_id : Z) (plaintext : list Z) (rks : list Z) :=
  Int.xor (get_uint32_le plaintext (col_id * 4)) (Int.repr (Znth col_id rks 0)).

  remember (exp_key ++ list_repeat 8 0) as buf. (* TODO when did this go lost? *)

  (* TODO do this earlier *)
  do 4 match goal with
  | |- context [temp _ (Vint (Int.xor (get_uint32_le plaintext ?i4) (Int.repr (Znth ?i buf 0))))] =>
       change (Int.xor (get_uint32_le plaintext i4) (Int.repr (Znth i buf 0)))
        with (mbed_tls_initial_add_round_key_col i plaintext buf)
  end.

Definition mbed_tls_initial_add_round_keyCORRECT (plaintext : list Z) (rks : list Z) : four_ints :=
((mbed_tls_initial_add_round_key_col 0 plaintext rks),
((mbed_tls_initial_add_round_key_col 1 plaintext rks),
((mbed_tls_initial_add_round_key_col 2 plaintext rks),
((mbed_tls_initial_add_round_key_col 3 plaintext rks))))).

  pose (S0 := mbed_tls_initial_add_round_keyCORRECT plaintext buf).
Definition col (i : Z) (s : four_ints) : int := match i with
| 0 => fst s
| 1 => fst (snd s)
| 2 => fst (snd (snd s))
| 3 => snd (snd (snd s))
| _ => Int.zero (* should not happen *)
end.

  match goal with |- context [temp _X0 (Vint ?E)] => change E with (col 0 S0) end.
  match goal with |- context [temp _X1 (Vint ?E)] => change E with (col 1 S0) end.
  match goal with |- context [temp _X2 (Vint ?E)] => change E with (col 2 S0) end.
  match goal with |- context [temp _X3 (Vint ?E)] => change E with (col 3 S0) end.

Definition mbed_tls_froundCORRECT (cols : four_ints) (rks : list Z) (i : Z) : four_ints :=
match cols with (col0, (col1, (col2, col3))) =>
  ((mbed_tls_fround_col col0 col1 col2 col3 (Znth  i    rks Int.zero)),
  ((mbed_tls_fround_col col1 col2 col3 col0 (Znth (i+1) rks Int.zero)),
  ((mbed_tls_fround_col col2 col3 col0 col1 (Znth (i+2) rks Int.zero)),
   (mbed_tls_fround_col col3 col0 col1 col2 (Znth (i+3) rks Int.zero)))))
end.

  pose (S1 := mbed_tls_froundCORRECT S0 buf).

  match goal with |- context [temp _Y0 (Vint ?E)] => change E with (col 0 S1) end.
  match goal with |- context [temp _Y1 (Vint ?E)] => change E with (col 1 S1) end.
  match goal with |- context [temp _Y2 (Vint ?E)] => change E with (col 2 S1) end.
  match goal with |- context [temp _Y3 (Vint ?E)] => change E with (col 3 S1) end.

  admit.
}
}
{ (* loop decr *)
admit.
}
}
}
{
admit.
}

Qed.

(* TODO floyd: sc_new_instantiate: distinguish between errors caused because the tactic is trying th
   wrong thing and errors because of user type errors such as "tuint does not equal t_struct_aesctx" *)

(* TODO floyd: compute_nested_efield should not fail silently *)

(* TODO floyd: if field_address is given a gfs which doesn't match t, it should not fail silently,
   or at least, the tactics should warn.
   And same for nested_field_offset. *)

(* TODO floyd: I want "omega" for int instead of Z 
   maybe "autorewrite with entailer_rewrite in *"
*)

(* TODO floyd: when load_tac should tell that it cannot handle memory access in subexpressions *)

(* TODO floyd: for each tactic, test how it fails when variables are missing in Pre *)

(*
Note:
field_compatible/0 -> legal_nested_field/0 -> legal_field/0:
  legal_field0 allows an array index to point 1 past the last array cell, legal_field disallows this
*)
