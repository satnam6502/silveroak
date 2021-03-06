(****************************************************************************)
(* Copyright 2021 The Project Oak Authors                                   *)
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

Require Import Coq.Lists.List.
Require Import Coq.Vectors.Vector.
Require Import ExtLib.Structures.Monads.
Import ListNotations VectorNotations MonadNotation.
Open Scope monad_scope.

Require Import Cava.Core.Core.
Require Import Cava.Lib.CavaPrelude.
Require Import Cava.Lib.Combinators.
Require Import Cava.Util.Vector.

(**** IMPORTANT: if you make changes to the API of these definitions, or add new
      ones, make sure you update the reference at docs/reference.md! ****)

Section WithCava.
  Context `{semantics:Cava}.

  (* Build a half adder *)
  Definition halfAdder '(x, y) :=
    partial_sum <- xor2 (x, y) ;;
    carry <- and2 (x, y) ;;
    ret (partial_sum, carry).

  (* A full adder *)
  Definition fullAdder '(cin, (x, y))
                       : cava (signal Bit * signal Bit) :=
    '(xyl, xyh) <- halfAdder (x, y) ;;
    '(xycl, xych) <- halfAdder (xyl, cin) ;;
    cout <- or2 (xyh, xych) ;;
    ret (xycl, cout).

  (* Unsigned adder for n-bit vectors with carry bits both in and out *)
  Definition addC {n : nat}
             (inputs : signal (Vec Bit n) * signal (Vec Bit n) * signal Bit) :
    cava (signal (Vec Bit n) * signal Bit) :=
    let '(x, y, cin) := inputs in
    x <- unpackV x ;;
    y <- unpackV y ;;
    col fullAdder cin (vcombine x y).

  (* Unsigned adder for n-bit vectors with bit-growth and no carry bits in or out *)
  Definition addN {n : nat}
            (xy: signal (Vec Bit n) * signal (Vec Bit n)) :
    cava (signal (Vec Bit n)) :=
    '(sum, _) <- addC (xy, zero) ;;
    ret sum.

  (* Increment an n-bit vector, representing result as an n-bit vector and a
     carry bit *)
  Definition incrC {n : nat} : signal (Vec Bit n) -> cava (signal (Vec Bit n) * signal Bit) :=
    match n with
    | 0 => fun input => ret (input, one) (* incrementing a 0-length vector always overflows *)
    | S m =>
      fun input : signal (Vec Bit (S m)) =>
        (* use synthesizable adder to add 1 *)
        onev <- packV [one] ;;
        sum <- unsignedAdd (input, onev) ;;
        (* resize (1 + Nat.max (S m) 1) to S (S m) *)
        sum <- Vec.resize_default (S (S m)) sum ;;
        (* separate highest bit from rest of sum *)
        sum_low <- Vec.shiftout sum ;;
        sum_high <- Vec.last sum ;;
        ret (sum_low, sum_high)
    end.

  (* Increment an n-bit vector with no bit-growth *)
  Definition incrN {n : nat} (input : signal (Vec Bit n)) : cava (signal (Vec Bit n)) :=
    '(out, _) <- incrC input ;;
    ret out.

  Section XilinxAdders.
    (* Build a full-adder with explicit use of Xilinx FPGA fast carry logic *)
    Definition xilinxFullAdder '(cin, (x, y))
    : cava (signal Bit * signal Bit) :=
      part_sum <- xor2 (x, y) ;;
      sum <- xorcy (part_sum, cin) ;;
      cout <- muxcy part_sum cin x  ;;
      ret (sum, cout).

    (* An unsigned adder built using the fast carry full-adder.*)
    Definition xilinxAdderWithCarry {n: nat}
               (xyc : signal (Vec Bit n) * signal (Vec Bit n) * signal Bit)
      : cava (signal (Vec Bit n) * signal Bit)
      := let '(x, y, cin) := xyc in
         x <- unpackV x ;;
         y <- unpackV y ;;
         col xilinxFullAdder cin (vcombine x y).

    (* An unsigned adder with no bit-growth and no carry in or out *)
    Definition xilinxAdder {n: nat}
               (x y : signal (Vec Bit n))
      : cava (signal (Vec Bit n)) :=
      '(sum, carry) <- xilinxAdderWithCarry (x, y, zero) ;;
      ret sum.
  End XilinxAdders.
End WithCava.
