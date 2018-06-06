;
; gram-class.scm
;
; Merge words into grammatical categories.
;
; Copyright (c) 2017, 2018 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; When a pair of words are judged to be grammatically similar, they
; can be used to create a "grammatical class", containing both the
; words, and behaving as their union/sum.  When a word is judged to
; belong to an existing grammatical-class, then some mechanism must
; be provided to add that word to the class.  This file implements
; the tools for creating and managing such classes.  It does not
; dictate how to judge when words belong to a class; this is done
; independently of the structure of the classes themselves.
;
; The above describes the general concept of "agglomerative clustering",
; which is what is effectively implemented in this file.  Note, however,
; that the general problem is not quite this simple: in addition to
; assigning words to grammatical classes, one must also cluster the
; connectors, which in turn alters the notion of similarity. That is,
; words are not isolated points to be clustered; the location of those
; "points" depend on the connectors and sections ("disjuncts") which
; must also be clustered in a consistent manner: these two clustering
; steps form a feedback loop.
;
;
; Representation
; --------------
; A grammatical class is represented as
;
;     MemberLink
;         WordNode "wordy"      ; the word itself
;         WordClassNode "noun"  ; the grammatical class of the word.
;
; Word classes have a designated grammatical behavior, using Sections,
; behaving just like the pseudo-connectors on single words. Thus, either
; a WordNode or a WordClassNode can appear in a Connector link, as
; shown below.
;
;     Section
;         WordClassNode "noun"
;         ConnectorSeq
;             Connector
;                WordClassNode "verb" ; or possibly a WordNode
;                LgConnDirNode "+"
;             Connector
;                ....
;
; Basic assumptions
; -----------------
; It is assumed that grammatical classes are stepping stones to word
; meaning; that meaning and grammatical class are at least partly
; correlated. It is assumed that words can have multiple meanings, and
; thus can belong to multiple grammatical classes. It is assumed that
; the sum total number of observations of a word is a linear combination
; of the different ways that the word was used in the text sample.
; Thus, the task is to decompose the observed counts on a single word,
; and assign them to one of several different grammatical classes.
;
; The above implies that each word should be viewed as a vector; the
; disjuncts form the basis of the vector space, and the count of
; observations of different disjuncts indicating the direction of the
; vector. It is the linearity of the observations that implies that
; such a vector-based linear approach is correct.
;
; The number of grammatical classes that a word might belong to can
; vary from a few to a few dozen; in addition, there will be some
; unknown amount of "noise": incorrect sections due to incorrect parses.
;
; It is assumed that when a word belongs to several grammatical classes,
; the sets of disjuncts defining those classes are not necessarily
; disjoint; there may be significant overlap. That is, different
; grammatical classes are not orthogonal, in general.
;
;
; Word Similarity
; ---------------
; There are several different means of comparing similarity between
; two words.  The simplest is cosine distance: if the cosine of two
; word-vectors is greater than a threshold, they should be merged.
;
; The cosine-distance is a user tunable parameter in the code below;
; it is currently hard-coded to 0.65.
;
; Other similarity measures are possible, but have not yet been
; explored.
;
;
; Semantic disambiguation
; -----------------------
; The correct notion of a grammatical class is not so much as a
; collection of words, but rather as a collection of word-senses.
; Consider the word "saw": it can be the past tense of the verb
; "to see", or it can be the cutting tool, a noun.  Thus, the word
; "saw" should belong to at least two different grammatical classes.
; The actual word-sense is "hidden", only the actual word is observed.
; The "hidden" word-sense can be partly (or mostly) discerned by looking
; at how the word was used: nouns are used differently than verbs.
; The different usage is reflected in the collection of sections
; ("disjuncts") that are associated with the word-sense.
;
; Thus, the vector associated to the word "saw" is the (linear) sum
; for a noun-vector (the cutting tool) and two different verb-vector
; (observing; cutting).  This section describes how the cosine-distance
; can be used to distinguish between these different forms, how to
; factor the vector of observation counts into distinct classes.
;
; The cosine distance between the two words w_a, w_b is
;
;    cos(w_a, w_b) = v_a . v_b / |v_a||v_b|
;
; Where, as usual, v_a . v_b is the dot product, and |v| is the length.
; The vector v_b can be decomposed into parallel and perpendicular parts:
;
;   v_b = v_llel + v_perp
;
;   v_llel = v_a |v_b| cos() / |v_a|
;   v_perp = v_b - v_llel
;
; which has the properties that v_llel points in the same direction as
; v_a and v_perp is perpendicular to v_a.  Now, because v_perp involves
; a subtraction, there will be, in general, vector components in v_perp
; that are negative (as mentioned above). However, if all vector
; components of v_perp are positive, then we can conclude that v_b can
; be decomposed into "two meanings" (or more).  One "meaning" is indeed
; v_a (i.e. is v_llel), the second meaning is v_perp.
;
; It seems reasonable to expect that "saw" would obey this relationship,
; with w_a == observe, w_b == saw, w_perp == cut. (This example ignores
; "saw == cutting tool").
;
; However, if v_perp has lots of negative components, then such an
; orthogonalization seems incorrect. That is, suppose that some other
; v_a and v_b had a small cosine distance (viz are almost collinear) but
; v_perp had many negative components. One cannot reasonably expect
; v_perp to identify "some other meaning" for v_b. Instead, it would
; seem that v_perp just consists of grunge that "should have been" in
; v_a, but wasn't.
;
; That is, due to a limited (small) number of observations, the negative
; coefficients in v_perp correspond to ways in which the word w_b was
; (observed to have been) used in a sentence, and a way that word w_a
; might have been used in a sentence, but wasn't (hadn't been observed).
; At least, this is the operational hypothesis, here.
;
; Thus, correct merge algo would seem to be:
;
;   Let w_a be an existing cluster
;   Let w_b be a candidate word to be merged into the cluster.
;   Compute v_llel and v_perp.
;   Let v_clamp = v_perp with negative components set to zero.
;   Let v_a^new = v_a + v_llel + (v_b - v_clamp)
;   Let v_b^new = v_clamp
;
; This would seem to have the effect of "broadening" v_a with missing
; vector components, while cleanly extracting the semantically different
; parts of v_b and sticking them into v_bnew.
;
; It seems reasonable to parameterize the above with a tunable parameter
; 0 <= alpha <= 1 so that
;
;   Let v_a^new = v_a + v_llel + alpha (v_b - v_clamp)
;
; It might also be useful replace `alpha (v_b - v_clamp)` by a sigmoid
; function `sigmoid(v_b - v_clamp)`, possibly incorporating the absolute
; values |v_b| and |v_clamp| into the sigmoid.
;
; The above "semantic merge" vector merge algorithm should be taken
; as a rough argument or hypothesis for extracting "hidden" word-senses
; from observation probabilities. There is currently no formal data
; analysis to support or reject this hypothesis, or to measure the
; quality the results it generates.
;
;
; merge-semantic
; --------------
; The above-described "semantic disambiguation" merge algorithm is
; implemented below, in the `merge-semantic` function.
;
; The above seems adequate when w_a is an existing cluster that is
; already well-aligned with a single word-sense. However, there is
; a boot-strapping problem: when two words are merged for the first
; time to create a new cluster, how can one be assured that this new
; seed-cluster is limited to only one word-sense?
;
; The solution to this would seem to be to perform an "overlap merge":
; that is, to compute the intersection of basis elements (the
; intersection of "disjuncts" aka "sections") of the two words, and
; then sum the counts only on this intersected set.  That is, let
;
;   {e_a} = set of basis elements in v_a with non-zero coefficients
;   {e_b} = set of basis elements in v_b with non-zero coefficients
;   {e_overlap} = {e_a} set-intersection {e_b}
;   v_o = vector of {e_overlap} i.e. having unit coeffs for each basis.
;   pi_overlap = v_o v_o^transpose
;              == projection matrix onto the subspace {e_overlap}
;   v_a^pi = pi_overlap . v_a == projection of v_a onto {e_overlap}
;   v_b^pi = pi_overlap . v_b == projection of v_b onto {e_overlap}
;
;   v_cluster = v_a^pi + v_b^pi
;   v_a^new = v_a - v_a^pi
;   v_b^new = v_b - v_b^pi
;
; The idea here is that the vector subspace {e_overlap} consists of
; those grammatical usages that are common for both words a and b,
; and thus hopefully correspond to how words a and b are used in a
; common sense. Thus v_cluster is the common word-sense, while v_a^new
; and v_b^new are everything else, everything left-over.  Note that
; v_a^new and v_b^new are orthogonal to v_cluster.
;
; Of course, this is not quite correct, if v_a and v_b have several
; word-senses in common; then v_cluster will be an amalgam of both.
;
;
; Alternative Merge Strategies
; ----------------------------
; Insofar as the above "semantic merge" aglorithm describes "hidden"
; meanings infered from observation probabilities, it is plausible to
; assume that perhaps a Hidden Markov Model (HMM) style approach might
; provide better results, or that alternately, an Artificial Neural
; Net (ANN), possibly with deep-learning, might provide a better
; factorization. At this time, these remain unexplored.
;
;
; Simpler Merge Algos
; -------------------
; Besides the above "semantic disambiguation" merge algorithm, there
; are several other, very slightly simpler ways in which two words
; might be merged into a word-class, or a word added to a word-class.
; These are described below. Compared to the above, the gut sense is
; that they are "less correct"; however, there is so far no data
; analysis by which to judge thier utility.
;
;
; Union word-pair merging
; ------------------------
; Given two words, add them as vectors, creating a new vector, the
; word-class. This is purely linear summation. Next, compute the
; orthogonal components of the words to the word-class, and replace
; the words by their orthogonal components - i.e. subtract the parallel
; components. It seems best to avoid negative observation counts, so
; if any count on any section is negative, it is clamped to zero (i.e.
; that section is removed, as this is a sparse vector). This last step
; renders this process only quasi-linear.
;
; Note the following properties of this algo:
; a) The combined vector has strictly equal or larger support than
;    the parts. This might not be correct, as it seems that it will
;    mix in disjuncts that should have been assigned to other meanings.
;    (the SUPPORT issue; discussed further below).
; b) The process is not quite linear, as orthogonal components with
;    negative counts are clamped to zero.
;    (the LEXICAL issue; discussed further, below)
; c) The number of vectors being tracked in the system is increasing:
;    before there were two, once for each word, now there are three:
;    each word remains, with altered counts, as well as their sum.
;    It might be nice to prune the number of vectors, so that the
;    dataset does not get outrageously large. Its possible that short
;    vectors might be mostly noise.
; d) There is another non-linearity, when a word is assigned to an
;    existing word-class. This assignment will slightly alter the
;    direction of the word-class vector, but will not trigger the
;    recomputation of previous orthogonal components.
; e) The replacement of word-vectors by their orthogonal components
;    means that the original word vectors are "lost". This could be
;    avoided by creating new "left-over" word vectors to hold just
;    the orthogonal components. However, this increases the size of
;    the dataset, and does not seem to serve any useful purpose.
;
;
; Overlap merging
; ---------------
; Similar to the above, a linear sum is taken, but the sum is only over
; those disjuncts that both words share in common. This might be more
; appropriate for disentangling linear combinations of multiple
; word-senses. It seems like it could be robust even with lower
; similarity scores (e.g. when using cosine similarity).
;
; Overlap merging appears to solve the problem a) above (the SUPPORT
; issue), but, on the flip side, it also seems to prevent the discovery
; and broadening of the ways in which a word might be used.
;
;
; merge-ortho
; -----------
; The above two merge methods are implemented in the `merge-ortho`
; function. It takes, as an argument, a fractional weight which is
; used when the disjunct isn't shared between both words. Setting
; the weight to zero gives overlap merging; setting it to one gives
; union merging. Setting it to fractional values provides a merge
; that is intermediate between the two: an overlap, plus a bit more,
; viz some of the union.
;
; In the code below, this is currently a hard-coded parameter, set to
; the ad hoc value of 0.3.  Behavior with different values is unexplored.
;
;
; Agglomerative clustering
; ------------------------
; The de facto algorithm implemented here is agglomerative clustering.
; That is, each word is compared to each of the existing clusters, and
; if it is close enough, it is merged in.  If a word cannot be assigned
; to a cluster, it is treated as a new cluster-point, and is tacked onto
; the list of existing clusters.
;
; That is, the existing clusters act as a sieve: new words either fall
; into one of the existing "holes", or start a new "hole".
;
; XXX Except this is not what the code actually does, as written. It
; deviates a bit from this, in a slightly wacky fashion. XXX FIXME.
;
;
; Broadening
; ----------
; The issue described in a) is an issue of broadening the known usages
; of a word, beyond what has been strictly observed in the text.  There
; are two distinct opportunities to broaden: first, in the union vs.
; overlap merging above, and second, in the merging of disjuncts. That
; is, the above merging did not alter the number of disjuncts in use:
; the disjuncts on the merged class are still disjuncts with single-word
; connectors. At some point, disjuncts should also be merged, i.e. by
; merging the connectors on them.
;
; If disjunct merging is performed after a series of word mergers have
; been done, then when a connector-word is replaced by a connector
; word-class, that class may be larger than the number of connectors
; originally witnessed. Again, the known usage of the word is broadened.
;
;
; Disjunct merging
; ----------------
; Disjunct merging is the second step in creating grammatical classes.
; The idea here is to replace individual connectors that specify words
; with connectors that specify word-classes. This step is examined in
; greater detail in `cset-class.scm`.
;
; ---------------------------------------------------------------------

(use-modules (srfi srfi-1))
(use-modules (opencog) (opencog matrix) (opencog persist))

; ---------------------------------------------------------------------

(define (merge-semantic LLOBJ FRAC WA WB)
"
  merge-semantic FRAC WA WB - merge WB into WA, returning the merged
  class.  If WA is a word, and not a class, then a new class is created
  and returned. The counts on both WA and WB are altered.

  WA should be a WordNode or a WordClassNode.
  WB is expected to be a WordNode.
  FRAC should be a floating point nummber between zero and one,
     indicating the fraction of the non-shared count of WB to be
     merged into WA. Setting this to a non-zero value broadens
     the class. Setting this to 1.0 gives the "pure" semantic merge
     (described in the primary docs).
  LLOBJ is used to access counts on pairs.  Pairs are SectionLinks,
     that is, are (word,disjunct) pairs wrapped in a SectionLink.

  The merger of WB into WA is performed, using the 'semantic
  merge' strategy. This is done like so. If WA and WB are both
  WordNodes, then a WordClass is created, having both WA and WB as
  members.  The counts on that word-class are the sum of the counts
  on the subspace defined by the intersection of WA and WB. (See main
  docs on the definition of this intersection/projection). Next, the
  counts on WA and WB are adjusted, so that the projected components
  are removed, leaving only the orthogonal components that are
  orthogonal to the new cluster.

  If WA is a WordClassNode, and WB is a WordNode, then WB is merged
  into WA. Counts are adjusted according to the 'semantic merge' policy
  described in the main docs.
"
)

; ---------------------------------------------------------------------

(define (merge-ortho LLOBJ FRAC WA WB)
"
  merge-ortho FRAC WA WB - merge WA and WB into a grammatical class.
  Return the merged class.

  WA should be a WordNode or a WordClassNode.
  WB is expected to be a WordNode.
  FRAC should be a floating point nummber between zero and one,
     indicating the fraction of a non-shared count to be used.
     Setting this to 1.0 gives the sum of the union of supports;
     setting this to 0.0 gives the sum of the intersection of supports.
  LLOBJ is used to access counts on pairs.  Pairs are SectionLinks,
     that is, are (word,disjunct) pairs wrapped in a SectionLink.

  The merger of WA and WB are performed, using the 'orthogonal
  merge' strategy. This is done like so. If WA and WB are both
  WordNodes, then a WordClass is created, having both WA and WB as
  members.  The counts on that word-class are the sum of the counts
  on WA and WB. Next, the counts on WA and WB are adjusted, so that
  only the orthogonal components are left (that is, the parts
  orthogonal to the sum). Next, zero-clamping is applied, so that
  any non-positive components are erased.

  The counts are summed only if both counts are non-zero. Otherwise,
  only a FRAC fraction of a single, unmatched count is transfered.

  If WA is a WordClassNode, and WB is not, then WB is merged into
  WA.
"
	(define psa (add-dynamic-stars LLOBJ))
	(define (bogus a b) (format #t "Its ~A and ~A\n" a b))
	(define ptu (add-tuple-math LLOBJ bogus))

	; set-count ATOM CNT - Set the raw observational count on ATOM.
	(define (set-count ATOM CNT) (cog-set-tv! ATOM (cog-new-ctv 1 0 CNT)))

	; Create a new word-class out of the two words.
	; Concatenate the string names to get the class name.
	; If WA is already a word-class, just use it as-is.
	(define wrd-class
		(if (eq? 'WordClassNode (cog-type WA)) WA
			(WordClassNode (string-concatenate
					(list (cog-name WA) " " (cog-name WB))))))

	; Merge two sections into one section built from the word-class.
	; One or the other sections can be null. If both sections are not
	; null, then both are assumed to have exactly the same disjunct.
	;
	; This works fine for merging two words, or for merging
	; a word and a word-class.  It even works for merging
	; two word-classes.
	;
	; This is a fold-helper; the fold accumulates the length-squared
	; of the merged vector.
	(define (merge-word-pair SECT-PAIR LENSQ)
		; The two word-sections to merge
		(define lsec (first SECT-PAIR))
		(define rsec (second SECT-PAIR))

		; The counts on each, or zero.
		(define lcnt (if (null? lsec) 0 (LLOBJ 'pair-count lsec)))
		(define rcnt (if (null? rsec) 0 (LLOBJ 'pair-count rsec)))

		; Return #t if sect is a Word section, not a word-class section.
		(define (is-word-sect? sect)
			(eq? 'WordNode (cog-type (cog-outgoing-atom sect 0))))

		; If the other count is zero, take only a FRAC of the count.
		; But only if we are merging in a word, not a word-class;
		; we never want to shrink the support of a word-class, here.
		(define wlc (if
				(and (null? rsec) (is-word-sect? lsec))
				(* FRAC lcnt) lcnt))
		(define wrc (if
				(and (null? lsec) (is-word-sect? rsec))
				(* FRAC rcnt) rcnt))

		; Sum them.
		(define cnt (+ wlc wrc))

		; The cnt can be zero, if FRAC is zero.  Do nothing in this case.
		(if (< 0 cnt)
			(let* (
					; The disjunct. Both lsec and rsec have the same disjunct.
					(seq (if (null? lsec) (cog-outgoing-atom rsec 1)
							(cog-outgoing-atom lsec 1)))
					; The merged word-class
					(mrg (Section wrd-class seq))
				)

				; The summed counts
				(set-count mrg cnt)
				(store-atom mrg) ; save to the database.
			))

		; Return the accumulated sum-square length
		(+ LENSQ (* cnt cnt))
	)

	; The length-squared of the merged vector.
	(define lensq
		(fold merge-word-pair 0.0 (ptu 'right-stars (list WA WB))))

	; Given a WordClassNode CLS and a WordNode WRD, alter the
	; counts on the disjuncts on WRD, so that they are orthogonal
	; to CLS.  If the counts are negative, that word-disjunct pair
	; is deleted (from the database as well as the atomspace).
	; The updated counts are stored in the database.
	;
	(define (orthogonalize CLS WRD)

		; Fold-helper to compute the dot-product between the WRD
		; vector and the CLS vector.
		(define (compute-dot-prod CLAPR DOT-PROD)
			(define cla (first CLAPR))
			(define wrd (second CLAPR))

			; The counts on each, or zero.
			(define cc (if (null? cla) 0 (LLOBJ 'pair-count cla)))
			(define wc (if (null? wrd) 0 (LLOBJ 'pair-count wrd)))

			(+ DOT-PROD (* cc wc))
		)

		; Compute the dot-product of WA and the merged class.
		(define dot-prod
			(fold compute-dot-prod 0.0 (ptu 'right-stars (list CLS WRD))))
		(define unit-prod (/ dot-prod lensq))

		; (format #t "sum ~A dot-prod=~A length=~A unit=~A\n"
		;      WRD dot-prod lensq unit-prod)

		; Alter the counts on the word so that they are orthogonal
		; to the class. Assumes that the dot-prduct was previously
		; computed, and also that the mean-square length of the
		; class was also previously computed.
		(define (ortho CLAPR)
			(define cla (first CLAPR))
			(define wrd (second CLAPR))

			; The counts on each, or zero.
			; Both cla and wrd are actually Sections.
			(define cc (if (null? cla) 0 (LLOBJ 'pair-count cla)))
			(define wc (if (null? wrd) 0 (LLOBJ 'pair-count wrd)))

			; The orthogonal component.
			(define orth (if (null? wrd) -999
					(- wc (* cc unit-prod))))

			; Update count on postive sections;
			; Delete non-postive sections. The deletion is not just
			; from the atomspace, but also the database backend!
			(if (< 0 orth)
				(set-count wrd orth)
				(if (not (null? wrd))
					(begin
						; Set to 0 just in case the delete below can't happen.
						(set-count wrd 0)
						(cog-delete wrd))))

			; Update the database.
			(if (cog-atom? wrd) (store-atom wrd))

			; (if (< 3 orth) (format #t "Large remainder: ~A\n" wrd))
		)

		; Compute the orthogonal components
		(for-each ortho (ptu 'right-stars (list CLS WRD)))
	)

	(if (eq? 'WordNode (cog-type WA))
		(begin

			; Put the two words into the new word-class.
			(store-atom (MemberLink WA wrd-class))
			(store-atom (MemberLink WB wrd-class))

			(orthogonalize wrd-class WA)
			(orthogonalize wrd-class WB))

		; If WA is not a WordNode, assume its a WordClassNode.
		; The process is similar, but slightly altered.
		; We assume that WB is a WordNode, but perform no safety
		; checking to verify this.
		(begin
			; Add WB to the mrg-class (which is WA already)
			(store-atom (MemberLink WB wrd-class))

			; Redefine WB to be orthogonal to the word-class.
			(orthogonalize wrd-class WB))
	)
	wrd-class
)

; ---------------------------------------------------------------
; stub wrapper for word-similarity.
; Return #t if the two should be merged, else return #f
; WORD-A might be a WordClassNode or a WordNode.
; XXX do something fancy here.
;
; COSOBJ must offer the 'right-cosine method
;
(define (ok-to-merge COSOBJ WORD-A WORD-B)
	; (define pca (make-pseudo-cset-api))
	; (define psa (add-dynamic-stars pca))
	; (define pcos (add-pair-cosine-compute psa))

	; Merge them if the cosine is greater than this
	(define cut 0.65)

	(define (get-cosine) (COSOBJ 'right-cosine WORD-A WORD-B))

	(define (report-cosine)
		(let* (
; (foo (format #t "Start cosine ~A \"~A\" -- \"~A\"\n"
; (if (eq? 'WordNode (cog-type WORD-A)) "word" "class")
; (cog-name WORD-A) (cog-name WORD-B)))
				(start-time (get-internal-real-time))
				(sim (get-cosine))
				(now (get-internal-real-time))
				(elapsed-time (* 1.0e-9 (- now start-time))))

			(format #t "Cosine=~6F for ~A \"~A\" -- \"~A\" in ~5F secs\n"
				sim
				(if (eq? 'WordNode (cog-type WORD-A)) "word" "class")
				(cog-name WORD-A) (cog-name WORD-B)
				elapsed-time)
			(if (< cut sim) (display "------------------------------ Bingo!\n"))
			sim))

	; True, if sim is more than 0.9
	(< cut (report-cosine))
)

; ---------------------------------------------------------------
; Given a single word and a list of grammatical classes, attempt to
; assign the the word to one of the classes.
;
; Given a single word and a list of words, attempt to merge the word
; with one of the other words.
;
; In either case, return the class it was merged into, or just the
; original word itself, if it was not assigned to any of them.
; A core assumption here is that the word can be assigned to just one
; and only one class; thus, all merge determinations can be done in
; parallel.
;
; Run-time is O(n) in the length n of CLS-LST, as the word is
; compared to every element in the CLS-LST.
;
; See also the `assign-expand-class` function.
;
; WORD should be the WordNode to test.
; CLS-LST should be list of WordNodes or WordClassNodes to compare
;          to the WORD.
; LLOBJ is the object to use for obtaining counts.
; FRAC is the fraction of union vs. intersection during merge.
; (These last two are passed blindly to the merge function).
;
(define (assign-word-to-class LLOBJ FRAC WRD CLS-LST)

	; Return #t if cls can be merged with WRD
	(define (merge-pred cls) (ok-to-merge LLOBJ cls WRD))

	(let (; (cls (find merge-pred CLS-LST))
			(cls (par-find merge-pred CLS-LST))
		)
		(if (not cls)
			WRD
			(merge-ortho LLOBJ FRAC cls WRD)))
)

; ---------------------------------------------------------------
; Given a word or a grammatical class, and a list of words, scan
; the word list to see if any of them can be merged into the given
; word/class.  If so, then perform the merge, and return the
; word-class; else return the original word. If the initial merge
; can be performed, then the remainder of the list is scanned, to
; see if the word-class can be further enlarged.
;
; This is an O(n) algo in the length of WRD-LST.
;
; This is similar to `assign-word-to-class` function, except that
; the roles of the arguments are reversed, and this function tries
; to maximally expand the resulting class.
;
; WRD-OR-CLS should be the WordNode or WordClassNode to merge into.
; WRD-LST should be list of WordNodes to merge into WRD-OR-CLS.
; LLOBJ is the object to use for obtaining counts.
; FRAC is the fraction of union vs. intersection during merge.
; (These last two are passed blindly to the merge function).
;
(define (assign-expand-class LLOBJ FRAC WRD-OR-CLS WRD-LST)
	(if (null? WRD-LST) WRD-OR-CLS
		(let ((wrd (car WRD-LST))
				(rest (cdr WRD-LST)))
			; If the word can be merged into a class, then do it,
			; and then expand the class. Else try again.
			(if (ok-to-merge LLOBJ WRD-OR-CLS wrd)
				; Merge, and try to expand.
				(assign-expand-class LLOBJ FRAC
					(merge-ortho LLOBJ FRAC WRD-OR-CLS wrd) rest)
				; Else keep trying.
				(assign-expand-class LLOBJ FRAC WRD-OR-CLS rest))))
)

; ---------------------------------------------------------------
; Given a list of words, compare them pair-wise to find a similar
; pair. Merge these to form a grammatical class, and then try to
; expand that class as much as possible. Repeat until all pairs
; have been explored.  This is an O(N^2) algo in the length of the
; word-list!
; This returns a list of the classes that were created.
(define (classify-pair-wise LLOBJ FRAC WRD-LST)

	(define (check-pair WORD-A WORD-B CLS-LST)
		(if (ok-to-merge LLOBJ WORD-A WORD-B)
			(let ((grm-class (merge-ortho LLOBJ FRAC WORD-A WORD-B)))
				(assign-expand-class LLOBJ FRAC grm-class WRD-LST)
				(cons grm-class CLS-LST))))

	(fold-unordered-pairs '() check-pair WRD-LST)
)

; ---------------------------------------------------------------
; Given a word-list and a list of grammatical classes, assign
; each word to one of the classes, or, if the word cannot be
; assigned, treat it as if it were a new class. Return a list
; of all of the classes, the ones that were given plus the ones
; that were created.
;
; WRD-LST is the list of words to be assigned to classes.
;
; TRUE-CLS-LST is a list of word-classes that words might possibley
;     get assigned to. This list should consist of WordClassNodes.
;     It can be initially empty; pairs of words than can be merged,
;     will be, to start a new class.
;
; FAKE-CLS-LIST is a list of singleton word-classes: pseudo-classes
;     that have only a single word in them. The list itself must
;     consist of WordNodes. It can be initially empty; if a word
;     cannot be merged into any existing class, then it will start
;     a new singleton class.
;
; The runtime is approximately O(N^2) + O(TN) + O(FN) where
;     N == (length WRD-LST)
;     T == (length TRUE-CLS-LST)
;     F == (length FAKE-CLS-LST)
;
; Currently, typical runtimes are about 1 second per pair, or about
; 0.5*500*500 = 35 hours for 500 words. This is NOT fast.
;
(define (assign-to-classes LLOBJ FRAC TRUE-CLS-LST FAKE-CLS-LST WRD-LST)
	(format #t "----  To-do =~A num-clases=~A num-done=~A ~A ----\n"
		(length WRD-LST) (length TRUE-CLS-LST) (length FAKE-CLS-LST)
		(strftime "%c" (localtime (current-time))))

	; If the WRD-LST is empty, we are done; otherwise compute.
	(if (null? WRD-LST) TRUE-CLS-LST
		(let* ((wrd (car WRD-LST))
				(rest (cdr WRD-LST))
				; Can we assign the word to a class?
				(cls (assign-word-to-class LLOBJ FRAC wrd TRUE-CLS-LST)))

			; If the word was merged into an existing class, then recurse
			(if (eq? 'WordClassNode (cog-type cls))
				(assign-to-classes LLOBJ FRAC TRUE-CLS-LST FAKE-CLS-LST rest)

				; If the word was not assigned to an existing class,
				; see if it can be merged with any of the singlton
				; words in the "fake-class" list.
				(let* ((new-cls (assign-word-to-class LLOBJ FRAC wrd FAKE-CLS-LST))
						(is-new-cls (eq? 'WordClassNode (cog-type new-cls)))
						(new-true
							(if is-new-cls
								; Use append, not cons, so as to preferentially
								; choose the older classes, as opposed to the
								; newer ones.
								(append! TRUE-CLS-LST (list new-cls))
								; else the true class list doesn't change
								TRUE-CLS-LST))
						(new-fake
							(if is-new-cls
								FAKE-CLS-LST
								; if its just a word, append it to the fake list
								(append! FAKE-CLS-LST (list new-cls)))))
					(assign-to-classes LLOBJ FRAC new-true new-fake rest)))))
)

; ---------------------------------------------------------------
; Given a word-list and a list of grammatical classes, assign
; each word to one of the classes, or, if the word cannot be
; assigned, treat it as if it were a new class. Return a list
; of all of the classes, the ones that were given plus the ones
; that were created.
;
; A common use is to call this with an empty class-list, initially.
; In this case, words are compared pair-wise to see if they can be
; merged together, for a run-time of O(N^2) in the length N of WRD-LST.
;
; If CLS-LST is not empty, and is of length M, then the runtime will
; be roughly O(MN) + O(K^2) where K is what's left of the initial N
; words that have not been assigned to classes.
;
; If the class-list contains WordNodes (instead of the expected
; WordClassNodes) and a merge is possible, then that WordNode will
; be merged to create a class.
;
(define (block-assign-to-classes LLOBJ FRAC WRD-LST CLS-LST)
	(format #t "-------  Words remaining=~A Classes=~A ~A ------\n"
		(length WRD-LST) (length CLS-LST)
		(strftime "%c" (localtime (current-time))))

	; If the WRD-LST is empty, we are done; otherwise compute.
	(if (null? WRD-LST) CLS-LST
		(let* ((wrd (car WRD-LST))
				(rest (cdr WRD-LST))
				; Can we assign the word to a class?
				(cls (assign-word-to-class LLOBJ FRAC wrd CLS-LST)))

			; If the word was merged into an existing class, then recurse
			(if (eq? 'WordClassNode (cog-type cls))
				(block-assign-to-classes LLOBJ FRAC rest CLS-LST)

				; If the word was not assigned to an existing class,
				; see if it can be merged with any of the other words
				; in the word-list.
				(let* ((new-cls (assign-expand-class LLOBJ FRAC wrd rest))
						(new-lst
							(if (eq? 'WordClassNode (cog-type new-cls))
								; Use append, not cons, so as to preferentially
								; choose the older classes, as opposed to the
								; newer ones.
								; (cons new-cls CLS-LST)
								(append! CLS-LST (list new-cls))
								; else the old class-list
								CLS-LST)))
					(block-assign-to-classes LLOBJ FRAC rest new-lst)))))
)

; ---------------------------------------------------------------
; Given the list LST of atoms, trim it, discarding atoms with
; low observation counts, and then sort it, returning the sorted
; list, ranked in order of the observed number of sections on the
; word. (i.e. the sum of the counts on each of the sections).
;
; Words with fewer than MIN-CNT observations on them are discarded.
;
; Note: an earlier version of this ranked by the number of times
; each word was observed: viz:
;      (> (get-count ATOM-A) (get-count ATOM-B))
; However, for WordNodes, this does not work very well, as the
; observation count may be high from any-pair parsing, but
; infrequently used in MST parsing.
;
; The current version gets observation counts from the partial sums
; on the LLOBJ.  This is fine when starting from scratch, but gets
; distorted, as word-merges transfer counts from the word to the
; word-class, but fail to update the partial sums. XXX this needs
; fixing. XXX FIXME
;
(define (trim-and-rank LLOBJ LST MIN-CNT)
	(define pss (add-support-api LLOBJ))

	; nobs == number of observations
	(define (nobs WRD) (pss 'right-count WRD))

	; The support API won't work, if we don't have the wild-cards
	; in the atomspace before we sort. The wild-cards hold/contain
	; the support subtotals.
	(define start-time (get-internal-real-time))
	(for-each
		(lambda (WRD) (fetch-atom (LLOBJ 'right-wildcard WRD)))
		LST)

	(format #t "Finished fetching wildcards in ~5F sconds\n"
		(* 1.0e-9 (- (get-internal-real-time) start-time)))
	(format #t "Now trim to min of ~A observation counts\n" MIN-CNT)
	(sort!
		; Before sorting, trim the list, discarding words with
		; low counts.
		(filter (lambda (WRD) (<= MIN-CNT (nobs WRD))) LST)
		; Rank so that the highest support words are first in the list.
		(lambda (ATOM-A ATOM-B) (> (nobs ATOM-A) (nobs ATOM-B))))
)

; ---------------------------------------------------------------
; Loop over all words, attempting to place them into grammatical
; classes. This is an O(N^2) algorithm, and so several "cheats" are
; employed to maintain some reasonable amount of forward progress. So,
;
; A) The list of words is ranked by order of the number of
;    observations; thus punctuation and "the, "a" come first.
; B) The ranked list is divided into power-of-two ranges, and only
;    the words in a given range are compared to one-another.
;
; The idea is that it is unlikely that words with very different
; observational counts will be similar.  NOTE: this idea has NOT
; been empirically tested, yet.
;
; TODO - the word-class list should probably also be ranked, so
; we preferentially add to the largest existing classes.
;
; XXX There is a user-adjustable parameter used below, to
; control the ranking. It should be exposed in the API or
; something like that! min-obs-cutoff, chunk-block-size
;
(define (loop-over-words LLOBJ FRAC WRD-LST CLS-LST)
	; XXX Adjust the minimum cutoff as desired!!!
	; This is a tunable paramter!
	; Right now, set to 20 observations, minimum. Less
	; than this and weird typos and stuff get in.
	(define min-obs-cutoff 20)
	(define all-ranked-words (trim-and-rank LLOBJ WRD-LST min-obs-cutoff))

	; Been there, done that; drop the top-20.
	; (define ranked-words (drop all-ranked-words 20))
	; (define ranked-words all-ranked-words)
	; Ad hoc restart point. If we already have N classes, we've
	; surely pounded the cosines of the first N(N-1)/2 words into
	; a bloody CPU-wasting pulp. Avoid wasting CPU any further.
	(define ncl (length CLS-LST))
	(define ranked-words (drop all-ranked-words (* 0.35 ncl cnl)))

	(define (chunk-blocks wlist size clist)
		(if (null? wlist) '()
			(let* ((wsz (length wlist))
					; the smaller of word-list and requested size.
					(minsz (if (< wsz size) wsz size))
					; the first block
					(chunk (take wlist minsz))
					; the remainder
					(rest (drop wlist minsz))
					; perform clustering
					(new-clist (block-assign-to-classes LLOBJ FRAC chunk clist)))
				; Recurse and do the next block.
				; XXX the block sizes are by powers of 2...
				; perhaps they should be something else?
				(chunk-blocks rest (* 2 size) new-clist)
			)
		)
	)

	; The initial chunk block-size.  This is a tunable parameter.
	; Perhaps it should be a random number, altered between runs?
	(define chunk-block-size 20)
	(format #t "Start classification of ~A (of ~A) words, chunksz=~A\n"
		(length ranked-words) (length WRD-LST) chunk-block-size)
	(chunk-blocks ranked-words chunk-block-size CLS-LST)
)

; ---------------------------------------------------------------

; XXX FIXME the 0.3 is a user-tunable paramter, for how much of the
; non-overlapping fraction to bring forwards.
(define (do-it)
	(let* ((pca (make-pseudo-cset-api))
			(psa (add-dynamic-stars pca))
			(pcos (add-pair-cosine-compute psa))
			(start-time (get-internal-real-time))
		)

		(display "Start loading words and word-classes\n")
		(load-atoms-of-type 'WordNode)
		(load-atoms-of-type 'WordClassNode)
		; Verify that words have been loaded
		;  (define all-words (get-all-cset-words))
		; (define all-words (cog-get-atoms 'WordNode))
		(format #t "Finished loading ~A words in ~5f seconds\n"
			(length (cog-get-atoms 'WordNode))
			(* 1.0e-9 (- (get-internal-real-time) start-time)))
		(loop-over-words pcos 0.3
			(cog-get-atoms 'WordNode)
			(cog-get-atoms 'WordClassNode))
	)
)

; ---------------------------------------------------------------
; Example usage
;
; (load-atoms-of-type 'WordNode)          ; Typicaly about 80 seconds
; (define pca (make-pseudo-cset-api))
; (define psa (add-dynamic-stars pca))
;
; Verify that support is correctly computed.
; cit-vil is a vector of pairs for matching sections for "city" "village".
; Note that the null list '() means 'no such section'
;
; (define (bogus a b) (format #t "Its ~A and ~A\n" a b))
; (define ptu (add-tuple-math psa bogus))
; (define cit-vil (ptu 'right-stars (list (Word "city") (Word "village"))))
; (length cit-vil)
;
; Show the first three values of the vector:
; (ptu 'pair-count (car cit-vil))
; (ptu 'pair-count (cadr cit-vil))
; (ptu 'pair-count (caddr cit-vil))
;
; print the whole vector:
; (for-each (lambda (pr) (ptu 'pair-count pr)) cit-vil)
;
; Is it OK to merge?
; (define pcos (add-pair-cosine-compute psa))
; (ok-to-merge pcos (Word "run") (Word "jump"))
; (ok-to-merge pcos (Word "city") (Word "village"))
;
; Perform the actual merge
; (merge-ortho pcos 0.3 (Word "city") (Word "village"))
;
; Verify presence in the database:
; select count(*) from atoms where type=22;
