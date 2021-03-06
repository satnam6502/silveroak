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

Require Import Cava.Cava.
Require Import Cava.Lib.Vec.
Require Import AesSpec.StateTypeConversions.
Require Import AesSpec.Tests.CipherTest.
Require Import AesSpec.Tests.Common.
Local Open Scope vector_scope.

Module Notations.
  Notation state := (Vec (Vec (Vec Bit 8) 4) 4) (only parsing).
  Notation key := (Vec (Vec (Vec Bit 8) 4) 4) (only parsing).
  Notation keypair := (Vec (Vec (Vec (Vec Bit 8) 4) 4) 2) (only parsing).
End Notations.

(* A function to convert a matrix of nat values to a value of type state *)
Definition fromNatState (i : Vector.t (Vector.t nat 4) 4 ): Vector.t (Vector.t Byte.byte 4) 4
  := Vector.map (Vector.map (fun v => bitvec_to_byte (N2Bv_sized 8 (N.of_nat v)))) i.

(* A function to convert a state value to a matrix of nat values. *)
Definition toNatState (i: Vector.t (Vector.t Byte.byte 4) 4) : Vector.t (Vector.t nat 4) 4
  := Vector.map (Vector.map (fun v => N.to_nat (Bv2N (byte_to_bitvec v)))) i.

(* A function to convert a matrix of nat values to a matrix of bitvecs *)
Definition fromNatVec (i : Vector.t (Vector.t nat 4) 4 ): Vector.t (Vector.t (Vector.t bool 8) 4) 4
  := Vector.map (Vector.map (fun v => N2Bv_sized 8 (N.of_nat v))) i.

(* A function to convert a bitvec matrix to a nat matrix. *)
Definition toNatVec (i: Vector.t (Vector.t (Vector.t bool 8) 4) 4) : Vector.t (Vector.t nat 4) 4
  := Vector.map (Vector.map (fun v => N.to_nat (Bv2N v))) i.

Local Notation byte := (Vec Bit 8) (only parsing).
Local Notation "v [@ n ]" := (indexConst v n) (at level 1, format "v [@ n ]").

Section WithCava.
  Context {signal} {semantics : Cava signal}.

  Definition bitvec_to_signal {n : nat} (lut : Vector.t bool n) : signal (Vec Bit n) :=
    Vec.bitvec_literal lut.

  Definition bitvecvec_to_signal {a b : nat} (lut : Vector.t (Vector.t bool b) a)
    : cava (signal (Vec (Vec Bit b) a)) :=
    packV (Vector.map bitvec_to_signal lut).

  Definition natvec_to_signal_sized {n : nat} (size : nat) (lut : Vector.t nat n)
    : cava (signal (Vec (Vec Bit size) n)) :=
    bitvecvec_to_signal (Vector.map (nat_to_bitvec_sized size) lut).

  Definition aes_transpose {n m}
      (matrix : signal (Vec (Vec byte n) m))
    : cava (signal (Vec (Vec byte m) n)) :=
    Vec.transpose matrix.

  Definition aes_mul2
    (x : signal byte)
    : cava (signal byte) :=

    x0 <- x[@0] ;;
    x1 <- x[@1] ;;
    x2 <- x[@2] ;;
    x3 <- x[@3] ;;
    x4 <- x[@4] ;;
    x5 <- x[@5] ;;
    x6 <- x[@6] ;;
    x7 <- x[@7] ;;

    a <- xor2 (x0, x7) ;;
    b <- xor2 (x2, x7) ;;
    c <- xor2 (x3, x7) ;;

    packV
      [x7;
      a;
      x1;
      b;
      c;
      x4;
      x5;
      x6
      ].

  Definition aes_mul4
    : signal byte -> cava (signal byte) :=
    aes_mul2 >=> aes_mul2.

  Definition zero_byte : cava (signal byte) := Vec.const zero 8.

  (* function automatic logic [31:0] aes_circ_byte_shift(logic [31:0] in, logic [1:0] shift);
    logic [31:0] out;
    logic [31:0] s;
    s = {30'b0,shift};
    out = {in[8*((7-s)%4) +: 8], in[8*((6-s)%4) +: 8],
           in[8*((5-s)%4) +: 8], in[8*((4-s)%4) +: 8]};
    return out;
  endfunction *)
  Definition aes_circ_byte_shift (shift: nat) (input: signal (Vec byte 4)):
    cava (signal (Vec byte 4)) :=
    let indices := [4 - shift; 5 - shift; 6 - shift; 7 - shift] in
    let indices := Vector.map (fun x => Nat.modulo x 4) indices in
    Vec.map_literal (indexConst input) indices.

  Definition IDLE_S := bitvec_to_signal (nat_to_bitvec_sized 3 0).
  Definition INIT_S := bitvec_to_signal (nat_to_bitvec_sized 3 1).
  Definition ROUND_S := bitvec_to_signal (nat_to_bitvec_sized 3 2).
  Definition FINISH_S := bitvec_to_signal (nat_to_bitvec_sized 3 3).
  Definition CLEAR_S_S := bitvec_to_signal (nat_to_bitvec_sized 3 4).
  Definition CLEAR_KD_S := bitvec_to_signal (nat_to_bitvec_sized 3 5).

  Definition STATE_INIT := bitvec_to_signal (nat_to_bitvec_sized 2 0).
  Definition STATE_ROUND := bitvec_to_signal (nat_to_bitvec_sized 2 1).
  Definition STATE_CLEAR := bitvec_to_signal (nat_to_bitvec_sized 2 2).

  Definition KEY_FULL_ENC_INIT := bitvec_to_signal (nat_to_bitvec_sized 2 0).
  Definition KEY_FULL_DEC_INIT := bitvec_to_signal (nat_to_bitvec_sized 2 1).
  Definition KEY_FULL_ROUND := bitvec_to_signal (nat_to_bitvec_sized 2 2).
  Definition KEY_FULL_CLEAR := bitvec_to_signal (nat_to_bitvec_sized 2 3).

  Definition ADD_RK_INIT := bitvec_to_signal (nat_to_bitvec_sized 2 0).
  Definition ADD_RK_ROUND := bitvec_to_signal (nat_to_bitvec_sized 2 1).
  Definition ADD_RK_FINAL := bitvec_to_signal (nat_to_bitvec_sized 2 2).

  Definition KEY_INIT_INPUT := constant false.
  Definition KEY_INIT_CLEAR := constant true.

  Definition KEY_DEC_EXPAND := constant false.
  Definition KEY_DEC_CLEAR := constant true.

  Definition KEY_WORDS_0123 := bitvec_to_signal (nat_to_bitvec_sized 2 0).
  Definition KEY_WORDS_2345 := bitvec_to_signal (nat_to_bitvec_sized 2 1).
  Definition KEY_WORDS_4567 := bitvec_to_signal (nat_to_bitvec_sized 2 2).
  Definition KEY_WORDS_ZERO := bitvec_to_signal (nat_to_bitvec_sized 2 3).

  Definition AES_128 := bitvec_to_signal (nat_to_bitvec_sized 3 1).
  Definition AES_192 := bitvec_to_signal (nat_to_bitvec_sized 3 2).
  Definition AES_256 := bitvec_to_signal (nat_to_bitvec_sized 3 4).

  Definition ROUND_KEY_DIRECT := constant false.
  Definition ROUND_KEY_MIXED := constant true.

  Import BitVecNotations.
  Open Scope bitvec_scope.

  Definition aes_mvm_acc (acc: signal (Vec Bit 8)) (mat: cava (signal (Vec Bit 8))) (vec: cava (signal Bit))
    : cava (signal (Vec Bit 8)) :=
    vec <- vec ;;
    mat <- mat >>= Vec.map (fun x => and2 (x, vec)) ;;
    acc ^ mat.

  Definition aes_mvm (vec_b: signal (Vec Bit 8)) (mat_a: signal (Vec (Vec Bit 8) 8))
    : cava (signal (Vec Bit 8)) :=
    _1 <- aes_mvm_acc (bitvec_to_signal(nat_to_bitvec_sized 8 0)) mat_a[@0] vec_b[@7] ;;
    _2 <- aes_mvm_acc _1 mat_a[@1] vec_b[@6] ;;
    _3 <- aes_mvm_acc _2 mat_a[@2] vec_b[@5] ;;
    _4 <- aes_mvm_acc _3 mat_a[@3] vec_b[@4] ;;
    _5 <- aes_mvm_acc _4 mat_a[@4] vec_b[@3] ;;
    _6 <- aes_mvm_acc _5 mat_a[@5] vec_b[@2] ;;
    _7 <- aes_mvm_acc _6 mat_a[@6] vec_b[@1] ;;
    aes_mvm_acc _7 mat_a[@7] vec_b[@0] .

End WithCava.

(* These values are arbitrary and are to be used as inputs for generating
  SystemVerilog testbenches. The expected output tested in the generated test bench is created
  from the Cava semantics for AES sub components on these arbitrary inputs. *)
Definition test_state
  : Vector.t (Vector.t nat 4) 4
  := [[219; 19; 83; 69];
      [242; 10; 34; 92];
      [1; 1; 1; 1];
      [45; 38; 49; 76]
  ].

Definition test_key
  : Vector.t (Vector.t nat 4) 4
  := [[219; 19; 83; 69];
      [242; 10; 34; 92];
      [1; 1; 1; 1];
      [45; 38; 49; 76]
  ].

