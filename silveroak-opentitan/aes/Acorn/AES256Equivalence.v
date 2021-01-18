(****************************************************************************)
(* Copyright 2020 The Project Oak Authors                                   *)
(*                                                                          *)
(* Licensed under the Apache License, Version 2.0 (the "License")           *)
(* you may not use this file except in compliance with the License.         *)
(* You may obtain a copy of the License at                                  *)
(*                                                                          *)
(*     http://www.apache.org/licenses/LICENSE-2.0                           *)
(*                                                                          *)
(* Unless required by applicable law or agreed to in writing, software      *)
(* distributed under the License is distributed on an "AS IS" BASIS,        *)
(* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. *)
(* See the License for the specific language governing permissions and      *)
(* limitations under the License.                                           *)
(****************************************************************************)

Require Import Coq.Arith.PeanoNat.
Require Import Coq.Vectors.Vector.
Require Import Coq.Lists.List.
Require Import coqutil.Tactics.destr.
Require Import ExtLib.Structures.Monads.
Require Import Cava.BitArithmetic.
Require Import Cava.ListUtils.
Require Import Cava.Tactics.
Require Import Cava.VectorUtils.
Require Import Cava.Acorn.Acorn.
Require Import Cava.Acorn.MonadFacts.
Require Import Cava.Acorn.Identity.

Require Import AesSpec.AES256.
Require Import AesSpec.StateTypeConversions.
Require Import AesSpec.CipherProperties.
Require Import AesSpec.ExpandAllKeys.
Require Import AcornAes.AddRoundKey.
Require Import AcornAes.AddRoundKeyEquivalence.
Require Import AcornAes.CipherRound.
Require Import AcornAes.CipherEquivalence.
Require Import AcornAes.Common.
Import ListNotations.
Import Common.Notations.

Local Notation round_constant := (Vec Bit 8) (only parsing).
Local Notation round_index := (Vec Bit 4) (only parsing).

Axiom sub_bytes : forall {signal} {semantics : Cava signal} {monad : Monad cava},
    signal Bit -> signal state -> cava (signal state).
Axiom shift_rows : forall {signal} {semantics : Cava signal} {monad : Monad cava},
    signal Bit -> signal state -> cava (signal state).
Axiom mix_columns : forall {signal} {semantics : Cava signal} {monad : Monad cava},
    signal Bit -> signal state -> cava (signal state).

Axiom key_expand : forall {signal} {semantics : Cava signal} {monad : Monad cava},
    signal Bit -> signal round_index -> signal key * signal round_constant ->
    cava (signal key * signal round_constant).
Axiom key_expand_spec : nat -> t bool 128 * t bool 8 -> t bool 128 * t bool 8.
Axiom inv_key_expand_spec : nat -> t bool 128 * t bool 8 -> t bool 128 * t bool 8.

(* convenience definition for converting to/from flat keys in key * round
   constant pairs *)
Definition flatten_key (kr : combType key * combType round_constant)
  : t bool 128 * combType round_constant := (from_cols_bitvecs (fst kr), snd kr).
Definition unflatten_key (kr : t bool 128 * combType round_constant)
  : combType key * combType round_constant := (to_cols_bitvecs (fst kr), snd kr).
Lemma flatten_unflatten kr : flatten_key (unflatten_key kr) = kr.
Proof.
  cbv [flatten_key unflatten_key]. destruct kr; cbn [fst snd].
  autorewrite with conversions. reflexivity.
Qed.
Lemma unflatten_flatten kr : unflatten_key (flatten_key kr) = kr.
Proof.
  cbv [flatten_key unflatten_key]. destruct kr; cbn [fst snd].
  autorewrite with conversions. reflexivity.
Qed.
Hint Rewrite @unflatten_flatten @flatten_unflatten using solve [eauto] : conversions.

Axiom sub_bytes_equiv :
 forall st : t bool 128,
   from_cols_bitvecs
     (combinational (sub_bytes false (to_cols_bitvecs st))) = AES256.sub_bytes st.
Axiom shift_rows_equiv :
  forall st : t bool 128,
    from_cols_bitvecs
      (combinational (shift_rows false (to_cols_bitvecs st))) = AES256.shift_rows st.
Axiom mix_columns_equiv :
  forall st : t bool 128,
    from_cols_bitvecs
      (combinational (mix_columns false (to_cols_bitvecs st))) = AES256.mix_columns st.
Axiom key_expand_equiv :
  forall (i : nat) (k : t (t (t bool 8) 4) 4 * t bool 8),
    (i < 16)%nat ->
    combinational (key_expand false (nat_to_bitvec_sized _ i) k)
    = unflatten_key (key_expand_spec i (flatten_key k)).

Axiom inv_sub_bytes_equiv :
 forall st : t bool 128,
   from_cols_bitvecs
     (combinational (sub_bytes true (to_cols_bitvecs st))) = inv_sub_bytes st.
Axiom inv_shift_rows_equiv :
  forall st : t bool 128,
    from_cols_bitvecs
      (combinational (shift_rows true (to_cols_bitvecs st))) = inv_shift_rows st.
Axiom inv_mix_columns_equiv :
  forall st : t bool 128,
    from_cols_bitvecs
      (combinational (mix_columns true (to_cols_bitvecs st))) = inv_mix_columns st.
Axiom inv_key_expand_equiv :
  forall (i : nat) (k : t (t (t bool 8) 4) 4 * t bool 8),
    (i < 16)%nat ->
    combinational (key_expand true (nat_to_bitvec_sized _ i) k)
    = unflatten_key (inv_key_expand_spec i (flatten_key k)).

Hint Resolve add_round_key_equiv sub_bytes_equiv shift_rows_equiv
     mix_columns_equiv inv_sub_bytes_equiv inv_shift_rows_equiv
     inv_mix_columns_equiv : subroutines_equiv.

Definition full_cipher {signal} {semantics : Cava signal} {monad : Monad cava}
           (num_rounds_regular round_0 : signal (Vec Bit 4))
  : signal Bit -> signal key -> signal (Vec Bit 8) ->
    list (signal (Vec Bit 4)) -> signal state -> cava (signal state) :=
  cipher
    (round_index:=Vec Bit 4) (round_constant:=Vec Bit 8)
    sub_bytes shift_rows mix_columns add_round_key
    (fun k => is_decrypt <- one ;; mix_columns is_decrypt k)
    key_expand num_rounds_regular round_0.

Lemma full_cipher_equiv
      (is_decrypt : bool) (first_rcon : t bool 8)
      (first_key last_key : combType key)
      middle_keys (input : combType state) :
  let Nr := 14 in
  let all_keys_and_rcons :=
      all_keys (if is_decrypt
                then (fun i k => unflatten_key (inv_key_expand_spec i (flatten_key k)))
                else (fun i k => unflatten_key (key_expand_spec i (flatten_key k))))
               Nr (first_key, first_rcon) in
  let all_keys := List.map fst all_keys_and_rcons in
  let round_indices := map (fun i => nat_to_bitvec_sized 4 i) (List.seq 0 (S Nr)) in
  let middle_keys_flat :=
      if is_decrypt
      then List.map AES256.inv_mix_columns (List.map from_cols_bitvecs middle_keys)
      else List.map from_cols_bitvecs middle_keys in
  all_keys = (first_key :: middle_keys ++ [last_key])%list ->
  combinational
    (full_cipher (nat_to_bitvec_sized _ Nr) (nat_to_bitvec_sized _ 0) is_decrypt
                 first_key first_rcon round_indices input)
  = to_cols_bitvecs
      ((if is_decrypt then aes256_decrypt else aes256_encrypt)
         (from_cols_bitvecs first_key) (from_cols_bitvecs last_key) middle_keys_flat
         (from_cols_bitvecs input)).
Proof.
  cbv [full_cipher]; intros.

  destruct is_decrypt.
  { (* decryption *)
    erewrite inverse_cipher_equiv with (Nr:=14);
      [ |  lazymatch goal with
           | |- _ = (_ :: _ ++ [_])%list =>
             erewrite ?all_keys_ext
               by (intros; rewrite inv_key_expand_equiv by Lia.lia;
                   instantiate_app_by_reflexivity); solve [eauto]
           | _ => change (2^4)%nat with 16; (reflexivity || Lia.lia)
           end .. ].

    cbv [aes256_decrypt].

    (* Change key and state representations so they match *)
    erewrite equivalent_inverse_cipher_change_state_rep
      by eapply to_cols_bitvecs_from_cols_bitvecs.
    erewrite equivalent_inverse_cipher_change_key_rep
      with (projkey:=to_cols_bitvecs)
           (middle_keys_alt:=
              List.map inv_mix_columns (List.map from_cols_bitvecs middle_keys))
           (first_key_alt:=from_cols_bitvecs first_key)
           (last_key_alt:=from_cols_bitvecs last_key)
      by (try apply to_cols_bitvecs_from_cols_bitvecs;
          rewrite !List.map_map; apply List.map_ext;
          intros; rewrite <-inv_mix_columns_equiv;
          autorewrite with conversions; reflexivity).

    (* Prove that ciphers are equivalent because all subroutines are
       equivalent *)
    f_equal.
    eapply equivalent_inverse_cipher_subroutine_ext;
      eauto with subroutines_equiv. }
  { (* encryption *)
    erewrite cipher_equiv with (Nr:=14);
      [ |  lazymatch goal with
           | |- _ = (_ :: _ ++ [_])%list =>
             erewrite ?all_keys_ext
               by (intros; rewrite key_expand_equiv by Lia.lia;
                   instantiate_app_by_reflexivity); solve [eauto]
           | _ => change (2^4)%nat with 16; (reflexivity || Lia.lia)
           end .. ].

    cbv [aes256_encrypt].

    (* Change key and state representations so they match *)
    erewrite cipher_change_state_rep
      by eapply to_cols_bitvecs_from_cols_bitvecs.
    erewrite cipher_change_key_rep
      with (projkey:=to_cols_bitvecs)
           (middle_keys_alt:=List.map from_cols_bitvecs middle_keys)
      by (apply to_cols_bitvecs_from_cols_bitvecs ||
          (rewrite List.map_map; apply ListUtils.map_id_ext;
           intros; autorewrite with conversions; reflexivity)).

    (* Prove that ciphers are equivalent because all subroutines are
       equivalent *)
    f_equal.
    eapply cipher_subroutine_ext; eauto with subroutines_equiv. }
Qed.

Local Open Scope monad_scope.

Lemma decrypt_middle_keys_equiv (middle_keys : list (combType key)) :
  List.map (fun k => from_cols_bitvecs (combinational (mix_columns true k)))
           (List.rev middle_keys) =
  List.map inv_mix_columns (List.rev (List.map from_cols_bitvecs middle_keys)).
Proof.
  rewrite !List.map_rev. f_equal.
  rewrite List.map_map. apply List.map_ext; intro x.
  rewrite <-(to_cols_bitvecs_from_cols_bitvecs x).
  rewrite inv_mix_columns_equiv.
  autorewrite with conversions; reflexivity.
Qed.

(* TODO: define a downto/upto loop combinator and then prove the cipher in terms of that *)
Lemma full_cipher_inverse
      (is_decrypt : bool) (first_rcon last_rcon : t bool 8)
      (first_key last_key : combType key) (input : combType state) :
  let Nr := 14 in
  let all_keys_and_rcons :=
      all_keys (fun i k => unflatten_key (key_expand_spec i (flatten_key k)))
               Nr (first_key, first_rcon) in
  let round_indices := map (fun i => nat_to_bitvec_sized 4 i) (List.seq 0 (S Nr)) in
  (* last_key and last_rcon are correct *)
  (exists keys, all_keys_and_rcons = keys ++ [(last_key, last_rcon)]) ->
  (* inverse key expansion reverses key expansion *)
  (forall i kr,
      unflatten_key
        (inv_key_expand_spec
           (Nr - S i) (key_expand_spec i (flatten_key kr))) = kr) ->
  combinational
    ((full_cipher (nat_to_bitvec_sized _ Nr) (nat_to_bitvec_sized _ 0)
                  false first_key first_rcon round_indices >=>
      full_cipher (nat_to_bitvec_sized _ Nr) (nat_to_bitvec_sized _ 0)
                  true last_key last_rcon round_indices) input) = input.
Proof.
  cbv [mcompose]. intros [keys Hkeys] ?. simpl_ident.

  (* extract the first key and middle keys to match full_cipher_equiv *)
  lazymatch type of Hkeys with
    ?all_keys = _ =>
    let H := fresh in
    assert (1 < length all_keys) as H by length_hammer;
      rewrite Hkeys in H
  end.
  destruct keys; autorewrite with push_length in *; [ Lia.lia | ].
  rewrite <-app_comm_cons in *.
  let H := fresh in pose proof Hkeys as H; apply hd_all_keys in H; [ | Lia.lia ].
  subst.

  (* TODO(jadep): can ExpandAllKeys be improved to make this less awkward? *)
  erewrite !full_cipher_equiv.
  2:{
    rewrite Hkeys. cbn [map]. rewrite map_app. cbn [map fst].
    reflexivity. }
  2:{
    erewrite all_keys_inv_eq
      by (intros; lazymatch goal with
                  | |- _ = last _ _ => rewrite Hkeys, app_comm_cons, last_last; reflexivity
                  | _ => cbv beta; autorewrite with conversions; auto
                  end).
    rewrite Hkeys. cbn [map rev]. rewrite map_app, rev_unit. cbn [map rev fst].
    rewrite <-app_comm_cons. reflexivity. }

  autorewrite with conversions.
  do 2 rewrite map_rev.
  rewrite aes256_decrypt_encrypt.
  autorewrite with conversions.
  reflexivity.
Qed.

Redirect "FullCipherEquiv_Assumptions" Print Assumptions full_cipher_equiv.
Redirect "FullCipherInverse_Assumptions" Print Assumptions full_cipher_inverse.