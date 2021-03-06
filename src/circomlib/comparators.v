Require Import Coq.PArith.BinPosDef.
Require Import Crypto.Util.Decidable Crypto.Util.Notations.
Require Import Crypto.Algebra.Ring Crypto.Algebra.Field.

(* Circuit:
 * https://github.com/iden3/circomlib/blob/master/circuits/comparators.circom
 *)

Section _comparators.

Context {F eq zero one opp add sub mul inv div}
        {fld:@Hierarchy.field F eq zero one opp add sub mul inv div}
        {eq_dec:DecidableRel eq}.
Local Infix "=" := eq. Local Notation "a <> b" := (not (a = b)).
Local Infix "=" := eq : type_scope. Local Notation "a <> b" := (not (a = b)) : type_scope.
Local Notation "0" := zero.  Local Notation "1" := one.
Local Infix "+" := add. Local Infix "*" := mul.
Local Infix "-" := sub. Local Infix "/" := div.

Definition eqb := bool_rel_of_dec_rel eq.
Local Infix "=?" := eqb.

Ltac split_eqns :=
  repeat match goal with
  | [ |- _ /\ _ ] => split
  | [ H: exists _, _ |- _ ] => destruct H
  | [ H: {s | _ } |- _ ] => destruct H
  | [ H: _ /\ _ |- _ ] => destruct H
  end.


(***********************
 *       IsZero
 ***********************)

(* IsZero constraints *)
Definition IsZero_cons (_in _out _inv: F) :=
  _out = 1 - _in * _inv /\
  _in * _out = 0.

(* IsZero template (hides intermediate variables) *)
Definition IsZeroTemplate (_in _out: F) :=
  exists _inv, IsZero_cons _in _out _inv.

(* IsZero *)
Class IsZero : Type := mkIsZero
{ IsZeroin: F; 
  IsZeroout: F;
  IsZerocons: IsZeroTemplate IsZeroin IsZeroout}.

(* IsZero spec *)
Definition IsZero_spec (_in _out: F) :=
  (_in = 0 -> _out = 1) /\
  (~(_in = 0) -> _out = 0).

(* IsZero correctness theorem *)
Theorem IsZero_correct: forall _in _out,
IsZeroTemplate _in _out <-> IsZero_spec _in _out.
Proof using Type*.
  intros _in _out.
  split; intros H;
  unfold IsZeroTemplate, IsZero_spec, IsZero_cons in *.
  - repeat (split_eqns; intro); fsatz.
  - destruct (dec (eq _in 0)).
    exists 1; repeat split_eqns; intuition idtac; fsatz.
    exists (1/_in). repeat split_eqns. pose proof n. apply H0 in n. fsatz.
    fsatz.
Qed.

(* use Record to repr template *)
Theorem IsZeroSoundness: 
  forall (t : IsZero), IsZero_spec t.(IsZeroin) t.(IsZeroout).
Proof.
  intros. apply IsZero_correct. exact t.(IsZerocons).
Qed.

(***********************
 *       IsEqual
 ***********************)

(* IsEqual constraints *)
Definition IsEqual_cons x y _out := IsZeroTemplate (x-y) _out.

(* IsEqual template *)
Definition IsEqualTemplate := IsEqual_cons.

(* IsEqual *)
Class IsEqual : Type := mkIsEqual
{ IsEqualx: F; 
  IsEqualy: F; 
  IsEqualout: F; 
  IsEqualcons: IsEqualTemplate IsEqualx IsEqualy IsEqualout}.

(* IsEqual spec *)
Definition IsEqual_spec x y _out :=
  (x = y -> _out = 1) /\ (~ x = y -> _out = 0).

(* IsEqual correctness theorem *)
Theorem IsEqual_correct: forall x y _out,
  IsEqualTemplate x y _out <-> IsEqual_spec x y _out.
Proof using Type*.
  intros; unfold IsEqualTemplate, IsEqual_spec, IsEqual_cons in *;
  split; intro H;
  (* try applying correctness lemma to every hyp and conclusion *)
  match goal with
  | [ H: IsZeroTemplate _ _ |- _ ] => apply IsZero_correct in H
  | [ |- IsZeroTemplate _ _  ] =>  apply IsZero_correct
  end;
  unfold IsZero_spec in *;
  destruct (dec (x = y));
  try (assert (x - y = 0) by fsatz; intuition idtac);
  try (assert (x - y <> 0) by fsatz; intuition idtac).
Qed.

(* use Record to repr template *)
Theorem IsEqualSoundness: 
  forall (t : IsEqual), IsEqual_spec t.(IsEqualx) t.(IsEqualy) t.(IsEqualout).
Proof.
  intros. apply IsEqual_correct. exact t.(IsEqualcons).
Qed.

(***********************
 *      IsNotEqual
 ***********************)
Definition IsNotEqual_cons x y _out _tmp :=
  IsEqualTemplate x y _tmp /\ _out = 1 - _tmp.

Definition IsNotEqualTemplate x y _out :=
  exists _tmp, IsNotEqual_cons x y _out _tmp.

(* IsNotEqual *)
Class IsNotEqual : Type := mkIsNotEqual
{ IsNotEqualx: F; 
  IsNotEqualy: F; 
  IsNotEqualout: F; 
  IsNotEqualcons: IsNotEqualTemplate IsNotEqualx IsNotEqualy IsNotEqualout}.

Definition IsNotEqual_spec x y _out :=
  (x = y -> _out = 0) /\ (~ x = y -> _out = 1).

Theorem IsNotEqual_correct: forall x y _out,
  IsNotEqualTemplate x y _out <-> IsNotEqual_spec x y _out.
Proof.
  intros; unfold IsNotEqualTemplate, IsNotEqual_spec, IsNotEqual_cons in *;
  split; intro H.
  - split_eqns;
    apply IsEqual_correct in H; unfold IsEqual_spec in H;
    repeat (split_eqns; intros);
    destruct (dec (x = y)); intuition; fsatz.
  - destruct (dec (x = y));
    eexists; split;
    try apply IsEqual_correct; unfold IsEqual_spec;
    repeat (split_eqns; intros);
    intuition idtac; (reflexivity || fsatz).
Qed.

(* use Record to repr template *)
Theorem IsNotEqualSoundness: 
  forall (t : IsNotEqual), IsNotEqual_spec t.(IsNotEqualx) t.(IsNotEqualy) t.(IsNotEqualout).
Proof.
  intros. apply IsNotEqual_correct. exact t.(IsNotEqualcons).
Qed.

End _comparators.