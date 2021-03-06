Require Import Coq.Strings.String.
Require Import bedrock2.ProgramLogic.
Require Import coqutil.Map.Interface.

Ltac subst1_map m :=
  match m with
  | map.put ?m _ _ => subst1_map m
  | ?m => is_var m; subst m
  end.

Ltac map_lookup :=
  repeat lazymatch goal with
         | |- context [map.get ?l] =>
           try apply map.get_put_same; try eassumption;
           subst1_map l;
           rewrite ?map.get_put_diff by congruence
         end.

Ltac straightline_with_map_lookup :=
  lazymatch goal with
  | _ => straightline
  | |- exists v, map.get _ _ = Some v /\ _ =>
    eexists; split; [ solve [map_lookup] | ]
  end.

Ltac one_goal_or_solved t :=
  solve [t] || (t; [ ]).

Ltac invert_nobranch' H t :=
  first [ inversion H; clear H; subst; solve [t]
        | inversion H; clear H; subst; t; [ ] ].
Ltac invert_nobranch H :=
  invert_nobranch' H ltac:(try congruence).

Ltac invert_bool :=
  lazymatch goal with
  | H : (_ && _)%bool = true |- _ =>
    apply Bool.andb_true_iff in H; destruct H
  | H : (_ && _)%bool = false |- _ =>
    apply Bool.andb_false_iff in H; destruct H
  | H : negb _ = true |- _ =>
    apply Bool.negb_true_iff in H
  | H : negb _ = false |- _ =>
    apply Bool.negb_false_iff in H
  end.
