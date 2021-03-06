Require Import Coq.Lists.List.
Require Import Coq.micromega.Lia.
Require Import Coq.Init.Peano.
Require Import Coq.Arith.PeanoNat.
Require Import Coq.Arith.Compare_dec.
Require Import Coq.PArith.BinPosDef.
Require Import Coq.ZArith.BinInt Coq.ZArith.ZArith Coq.ZArith.Zdiv Coq.ZArith.Znumtheory Coq.NArith.NArith. (* import Zdiv before Znumtheory *)
Require Import Coq.NArith.Nnat.

Require Import Crypto.Spec.ModularArithmetic.
Require Import Crypto.Spec.ModularArithmetic.
Require Import Crypto.Arithmetic.PrimeFieldTheorems Crypto.Algebra.Field.


Require Import Crypto.Util.Tuple.
Require Import Crypto.Util.Decidable Crypto.Util.Notations.
Require Import BabyJubjub.
Require Import Coq.setoid_ring.Ring_theory Coq.setoid_ring.Field_theory Coq.setoid_ring.Field_tac.
Require Import Ring.

Require Import Util.

(* Require Import Crypto.Spec.ModularArithmetic. *)
(* Circuit:
* https://github.com/iden3/circomlib/blob/master/circuits/bitify.circom
*)

Section _bitify.

Local Open Scope list_scope.
Local Open Scope F_scope.

Ltac fqsatz := fsatz_safe; autorewrite with core; auto.

Context (q:positive) (k:Z) {prime_q: prime q} {two_lt_q: 2 < q} {k_positive: 1 < k} {q_lb: 2^k < q}.

Lemma q_gtb_1: (1 <? q)%positive = true.
Proof.
  apply Pos.ltb_lt. lia.
Qed.

Lemma q_gt_2: 2 < q.
Proof.
  replace 2%Z with (2^1)%Z by lia.
  apply Z.le_lt_trans with (m := (2 ^ k)%Z); try lia.
  eapply Zpow_facts.Zpower_le_monotone; try lia.
Qed.

Hint Rewrite q_gtb_1 : core.

(***********************
 *      Num2Bits
 ***********************)

(* test whether a field element is binary *)
Definition binary (x: F q) := x = 0 \/ x = 1.
Definition two : F q := 1 + 1.
Notation "2" := two.

Lemma to_Z_2: F.to_Z 2 = 2%Z.
Proof. simpl. repeat rewrite Z.mod_small; lia. Qed.


(* peel off 1 from x^(i+1) in field exp *)
Lemma pow_S_N: forall (x: F q) i,
  x ^ (N.of_nat (S i)) = x * x ^ (N.of_nat i).
Proof.
  intros.
  replace (N.of_nat (S i)) with (N.succ (N.of_nat i)).
  apply F.pow_succ_r.
  induction i.
  - reflexivity.
  - simpl. f_equal.
Qed.

(* peel off 1 from x^(i+1) in int exp *)
Lemma pow_S_Z: forall (x: Z) i,
  (x ^ (Z.of_nat (S i)) = x * x ^ (Z.of_nat i))%Z.
Proof.
  intros.
  replace (Z.of_nat (S i)) with (Z.of_nat i + 1)%Z by lia.
  rewrite Zpower_exp; lia.
Qed.

(* [repr]esentation [func]tion:
 * interpret a list of weights as representing a little-endian base-2 number
 *)
Fixpoint repr_to_le' (i: nat) (ws: list (F q)) : F q :=
  match ws with
  | nil => 0
  | w::ws' => w * two^(N.of_nat i) + repr_to_le' (S i) ws'
  end.

Definition repr_to_le := repr_to_le' 0%nat.

(* repr func lemma: single-step index change *)
Lemma repr_to_le'_S: forall ws i,
  repr_to_le' (S i) ws = 2 * repr_to_le' i ws.
Proof.
  induction ws as [| w ws]; intros.
  - fqsatz.
  - unfold repr_to_le'.
    rewrite IHws.
    replace (2 ^ N.of_nat (S i)) with (2 * 2 ^ N.of_nat i)
      by (rewrite pow_S_N; fqsatz).
    fqsatz.
Qed.

(* repr func lemma: multi-step index change *)
Lemma repr_to_le'_n: forall ws i j,
  repr_to_le' (i+j) ws = 2^(N.of_nat i) * repr_to_le' j ws.
Proof.
  induction i; intros; simpl.
  - rewrite F.pow_0_r. fqsatz.
  - rewrite repr_to_le'_S. rewrite IHi.
    replace (N.pos (Pos.of_succ_nat i)) with (1 + N.of_nat i)%N.
    rewrite F.pow_add_r.
    rewrite F.pow_1_r.
    fqsatz.
    lia.
Qed.

(* repr func lemma: decomposing weight list *)
Lemma repr_to_le_app: forall ws2 ws1 ws i,
  ws = ws1 ++ ws2 ->
  repr_to_le' i ws = repr_to_le' i ws1 + repr_to_le' (i + length ws1) ws2.
Proof.
  induction ws1; simpl; intros.
  - subst. replace (i+0)%nat with i by lia. fqsatz.
  - destruct ws; inversion H; subst.
    simpl.
    assert (repr_to_le' (S i) (ws1 ++ ws2) = 
      repr_to_le' (S i) ws1 + repr_to_le' (i + S (length ws1)) ws2). {
        rewrite <- plus_n_Sm, <- plus_Sn_m.
        eapply IHws1. reflexivity.
      }
    fqsatz.
Qed.

(* [repr]esentation [inv]ariant for Num2Bits *)
Definition repr_binary x n ws :=
  length ws = n /\
  (forall i, (i < n)%nat -> binary (nth i ws 0)) /\
  x = repr_to_le' 0%nat ws.

Fixpoint repr_to_le'_tuple {n} (i: nat) {struct n} : tuple' (F q) n -> F q :=
  match n with
  | O => fun t => 0
  | S n' => fun '(ws, w) => w * 2^(N.of_nat i) + @repr_to_le'_tuple n' (S i) ws
  end.

(* Definition repr_binary_tuple x n (ws: tuple (F q) n) :=
  (forall i, (i < n)%nat -> binary (nth_default 0 i ws)) /\
  x = repr_to_le'_tuple 0%nat ws. *)

(* repr inv: base case *)
Lemma repr_binary_base: repr_binary 0 0%nat nil.
Proof.
  unfold repr_binary.
  split; split.
  - intros. simpl. destruct i; unfold binary; auto.
  - reflexivity.
Qed.

(* repr inv: invert weight list *)
Lemma repr_binary_invert: forall w ws,
  repr_binary (repr_to_le (w::ws)) (S (length ws)) (w::ws) ->
  repr_binary (repr_to_le ws) (length ws) ws.
Proof.
  intros.
  destruct H as [H_len H_repr].
  destruct H_repr as [H_bin H_le].
  split; split.
  intros i Hi.
  specialize (H_bin (S i)).
  apply H_bin. lia.
  auto.
Qed.

(* repr inv: trivial satisfaction *)
Lemma repr_trivial: forall ws,
  (forall i, (i < length ws)%nat -> binary (nth i ws 0)) ->
  repr_binary (repr_to_le ws) (length ws) ws.
Proof.
  induction ws; unfold repr_binary; split; try split; intros; auto.
Qed.

(* repr inv: any prefix of weights also satisfies the inv *)
Lemma repr_binary_prefix: forall ws1 ws2 ws,
  ws = ws1 ++ ws2 ->
  repr_binary (repr_to_le ws) (length ws) ws ->
  repr_binary (repr_to_le ws1) (length ws1) ws1.
Proof.
  induction ws1; intros.
  - apply repr_trivial. simpl. lia.
  - rewrite H in H0. 
    pose proof (repr_binary_invert _ _ H0) as H_ws1_ws2.
    unfold repr_to_le.
    assert (repr_binary (repr_to_le ws1) (length ws1) ws1).
    eapply IHws1; eauto.
    split; split; eauto.
    intros i Hi.
    destruct H0. destruct H2.
    specialize (H2 i).
    assert (binary (nth i ((a :: ws1) ++ ws2) 0)).
    simpl in Hi.
    apply H2. simpl. rewrite app_length. lia.
    rewrite app_nth1 in H4. auto. lia.
Qed.

(* pseudo-order on field elements *)
Definition lt (x y: F q) := F.to_Z x <= F.to_Z y.
Definition lt_z (x: F q) y := F.to_Z x <= y.
Definition geq_z (x: F q) y := F.to_Z x >= y.
Definition leq_z (x: F q) y := F.to_Z x <= y.


(* repr inv: x <= 2^n - 1 *)
Theorem repr_binary_ub: forall ws x n,
  repr_binary x n ws ->
  Z.of_nat n <= k ->
  leq_z x (2^(Z.of_nat n)-1)%Z.
Proof with (lia || nia || eauto).
  unfold leq_z.
  induction ws as [| w ws]; intros x n H_repr H_n.
  - unfold repr_binary.
    destruct H_repr. destruct H0.
    subst. cbv. intros. inversion H.
  - (* analyze n: is has to be S n for some n *)
    destruct n; destruct H_repr; destruct H0; simpl in H...
    inversion H. subst. clear H.
    (* lemma preparation starts here *)
    (* assert IHws's antecedent holds *)
    assert (H_repr_prev: repr_binary (repr_to_le ws) (length ws) ws). {
      apply repr_trivial.
      intros i Hi. 
      specialize (H0 (S i)). apply H0...
    }
    (* extract consequence of IHws *)
    assert (IH: F.to_Z (repr_to_le ws) <= 2 ^ Z.of_nat (length ws) - 1). {
      apply IHws...
    }
    (* introduce lemmas into scope *)
    pose proof q_gt_2.
    (* bound |w| *)
    assert (H_w: 0 <= F.to_Z w <= 1). {
      assert (H_w_binary: binary w) by (specialize (H0 O); apply H0; lia).
      destruct H_w_binary; subst; simpl; rewrite Z.mod_small...
    }
    (* peel off 1 from 2^(x+1) *)
    pose proof (pow_S_Z 2 (length ws)) as H_pow_S_Z.
    (* bound 2^|ws| *)
    assert (H_pow_ws: 0 <= 2 * 2 ^ (Z.of_nat (length ws)) <= 2 ^ k). {
        replace (2 * 2 ^ (Z.of_nat (length ws)))%Z with (2 ^ (Z.of_nat (length ws) + 1))%Z.
        split...
        apply Zpow_facts.Zpower_le_monotone...
        rewrite Zpower.Zpower_exp...
      }
    (* F.to_Z x is nonneg *)
    assert (0 <= F.to_Z (repr_to_le ws)). {
      apply F.to_Z_range...
    }
    (* lemma preparation ends here *)
    (* actual proof starts here *)
    cbn [repr_to_le'].
    unfold repr_to_le in *.
    rewrite repr_to_le'_S.
    (* get rid of mod and generate range goals *)
    cbn; repeat rewrite Z.mod_small...
Qed.

Ltac to_Z_ranges :=
  match goal with
  | |- context[F.to_Z ?E] => assert (0 <= F.to_Z E < q) by (apply F.to_Z_range; lia)
  end.

(* repr inv: ws[i] = 1 -> x >= 2^i *)
Theorem repr_binary_lb: forall n ws x i,
  Z.of_nat n <= k ->
  repr_binary x n ws ->
  (i < n)%nat ->
  nth i ws 0 = 1 ->
  geq_z x (2^Z.of_nat i).
Proof.
  (* we can't do induction on ws, since we need to decompose
    (w :: ws) as (ms ++ [m]) in the inductive case *)
  induction n;
  intros ws x i H_n_k H_repr Hi H_ws_i;
  pose proof H_repr as H_repr';
  destruct H_repr as [H_len H_repr];
  destruct H_repr as [H_bin H_x]; simpl in H_len.
  
  (* base case *)
  subst. lia.
  
  (* inductive case *)
  destruct ws as [| w ws]; inversion H_len. subst.
  pose proof exists_last as ws_last.
  assert (H_last: w::ws <> nil). discriminate.
  (* rewrite w::ws as ms++[m] *)
  apply ws_last in H_last.
  destruct H_last as [ms H_last].
  destruct H_last as [m H_last].
  rewrite H_last.
  rewrite repr_to_le_app with (ws1 := ms) (ws2 := m::nil) by trivial.
  unfold geq_z. rewrite F.to_Z_add.
  replace (0 + length ms)%nat with (length ms) by lia.
  assert (H_ws: length ws = length ms). {
    (* FIXME: should be automated *)
    replace (length ws) with (length (w::ws) - 1)%nat by (simpl; lia).
    replace (length ms) with (length (ms ++ m :: nil) -1)%nat. 
    assert (length (w::ws) = length (ms ++ m :: nil)) by (f_equal; auto).
    lia.
    rewrite app_length. simpl. lia.
  }
  assert (H_pow_ms: 2 ^ N.of_nat (length ms) <= 2 ^ (k-1)). {
    apply Zpow_facts.Zpower_le_monotone; lia.
  }
  assert (H_pow_ms': 2 ^ N.of_nat (length ms) <= 2 ^ k). {
    apply Zpow_facts.Zpower_le_monotone; lia.
  }
  rewrite Z.mod_small.
  destruct (dec (i < length ws)%nat).
  + (* easy case: i < length ws, so simply apply IH *)
    assert (geq_z (repr_to_le' 0 ms) (2 ^ Z.of_nat i)). {
      eapply IHn with (ws := ms); auto.
      lia.
      rewrite H_ws.
      eapply repr_binary_prefix; eauto.
      rewrite H_last in *.
      erewrite <- app_nth1; eauto. lia.
    }
    unfold geq_z in H.
    assert (0 <= F.to_Z (repr_to_le' (length ms) (m :: nil)) < q) by (to_Z_ranges; auto).
    lia.
  + (* interesting case: i = length ws *)
    rewrite H_ws in *.
    assert (i = length ms) by lia. subst.
    to_Z_ranges.
    assert (F.to_Z (repr_to_le' (length ms) (m :: nil)) >= 2 ^ Z.of_nat (length ms)). {
      cbn [repr_to_le'].
      assert (m = 1). {
        rewrite H_last in H_ws_i.
        replace m with (nth (length ms) (ms ++ m :: nil) 0). auto.
        rewrite app_nth2 by lia.
        replace (length ms - length ms)%nat with 0%nat by lia.
        reflexivity.
      }
      subst.
      repeat rewrite F.to_Z_add, F.to_Z_mul, F.to_Z_pow, F.to_Z_0, (@F.to_Z_1 _ two_lt_q), to_Z_2.
      repeat rewrite Z.mod_small; lia.
    }
    lia.
  + (* range check *)
    cbn [repr_to_le']. 
    assert (H_m_bin: binary m). {
      destruct H_repr'. destruct H0.
      rewrite H_last in H0.
      specialize (H0 (length ms)).
      replace m with (nth (length ms) (ms ++ m :: nil) 0). apply H0. lia.
      rewrite app_nth2. replace (length ms - length ms)%nat with 0%nat. reflexivity.
      lia.
      lia.
    }
    assert (0 <= F.to_Z m <= 1). {
      destruct H_m_bin; subst; try rewrite @F.to_Z_0; try rewrite @F.to_Z_1; lia.
    }
    rewrite F.to_Z_add, F.to_Z_mul, F.to_Z_pow, to_Z_2.
    assert (H_ms_ub: leq_z (repr_to_le' 0 ms) (2 ^ Z.of_nat (length ms) - 1)). {
      eapply repr_binary_ub with (ws := ms).
      rewrite H_last in H_repr'.
      eapply repr_binary_prefix with (ws := ms). rewrite app_nil_r. reflexivity.
      apply repr_trivial.
      intros j Hj. destruct H_repr'. destruct H1.
      replace (nth j ms 0) with (nth j (ms ++ m :: nil) 0).
      apply H1. lia.
      rewrite app_nth1. reflexivity. lia. lia.
    }
    repeat rewrite Z.mod_small; try (
      lia || 
      destruct H_m_bin; subst; try rewrite @F.to_Z_0; try rewrite @F.to_Z_1; (lia || auto)).
      to_Z_ranges.
      lia.
    unfold leq_z in *.
    to_Z_ranges.
    remember (F.to_Z (repr_to_le' 0 ms)) as x.
    remember (2 ^ N.of_nat (length ms))%Z as y.
    assert (x <= 2^(k-1)) by lia.
    assert (x + y < 2^k). {
      replace (2^k)%Z with (2^1*2^(k-1))%Z.
      lia.
      rewrite <- Zpower_exp; f_equal; lia.
    }
    lia.
Qed.

Definition Num2Bits (n: nat) (_in: F q) (_out: tuple (F q) n) : Prop :=
  let lc1 := 0 in
  let e2 := 1 in
  let '(lc1, e2, _C) := (iter n (fun (i: nat) '(lc1, e2, _C) =>
    let out_i := (Tuple.nth_default 0 i _out) in
      (lc1 + out_i * e2,
      e2 + e2,
      (out_i * (out_i - 1) = 0) /\ _C))
    (lc1, e2, True)) in
  (lc1 = _in) /\ _C.

Theorem Num2Bits_correct n _in _out:
  Num2Bits n _in _out -> (forall i, (i < n)%nat -> binary (Tuple.nth_default 0 i _out)).
Proof.
  unfold Num2Bits.
  (* provide loop invariant *)
  pose (Inv := fun i '((lc1, e2, _C): (F.F q * F.F q * Prop)) =>
    (_C -> (forall j, (j < i)%nat -> binary (Tuple.nth_default 0 j _out)))).
  (* iter initialization *)
  remember (0, 1, True) as a0.
  intros prog i H_i_lt_n.
  (* iter function *)
  match goal with
  | [ H: context[match ?it ?n ?f ?init with _ => _ end] |- _ ] =>
    let x := fresh "f" in remember f as x
  end.
  (* invariant holds *)
  assert (Hinv: forall i, Inv i (iter i f a0)). {
  intros. apply iter_inv; unfold Inv.
  - (* base case *) 
    subst. intros _ j impossible. lia.
  - (* inductive case *)
    intros j res Hprev.
    destruct res. destruct p.
    rewrite Heqf.
    intros _ Hstep j0 H_j0_lt.
    destruct Hstep as [Hstep HP].
    specialize  (Hprev HP).
    destruct (dec (j0 < j)%nat).
    + auto.
    + unfold binary. intros.
      replace j0 with j by lia.
      destruct (dec (Tuple.nth_default 0 j _out = 0)).
      * auto.
      * right. fqsatz.
   }
  unfold Inv in Hinv.
  specialize (Hinv n).
  destruct (iter n f a0).
  destruct p.
  intuition.
Qed.

End _bitify.