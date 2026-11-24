
DROP TABLE IF EXISTS pg_temp.test_results;
CREATE TEMP TABLE test_results (n SERIAL, test TEXT, statut TEXT, detail TEXT);

-- t_ok : la requete doit s'executer SANS erreur
CREATE OR REPLACE FUNCTION pg_temp.t_ok(p_test TEXT, p_sql TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_statut TEXT := 'PASS'; v_detail TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION 'rollback_test' USING ERRCODE = 'ZZ001';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN NULL;
        WHEN OTHERS THEN v_statut := 'FAIL'; v_detail := SQLERRM;
    END;
    INSERT INTO test_results(test, statut, detail) VALUES (p_test, v_statut, v_detail);
END $$;

-- t_eq : la requete renvoie UNE valeur, comparee a la valeur attendue
CREATE OR REPLACE FUNCTION pg_temp.t_eq(p_test TEXT, p_sql TEXT, p_attendu TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_statut TEXT := 'PASS'; v_detail TEXT; v_val TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql INTO v_val;
        IF v_val IS DISTINCT FROM p_attendu THEN
            v_statut := 'FAIL';
            v_detail := 'attendu ' || p_attendu || ', obtenu ' || coalesce(v_val, 'NULL');
        END IF;
        RAISE EXCEPTION 'rollback_test' USING ERRCODE = 'ZZ001';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN NULL;
        WHEN OTHERS THEN v_statut := 'FAIL'; v_detail := SQLERRM;
    END;
    INSERT INTO test_results(test, statut, detail) VALUES (p_test, v_statut, v_detail);
END $$;

-- t_err : la requete doit lever une erreur CLAIRE (RAISE EXCEPTION)
CREATE OR REPLACE FUNCTION pg_temp.t_err(p_test TEXT, p_sql TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_statut TEXT := 'FAIL'; v_detail TEXT := 'aucune erreur levee';
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION 'rollback_test' USING ERRCODE = 'ZZ001';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN NULL;
        WHEN undefined_function THEN v_statut := 'FAIL'; v_detail := 'fonction absente : ' || SQLERRM;
        WHEN raise_exception THEN
            IF SQLERRM LIKE '%TODO%' THEN
                v_statut := 'FAIL'; v_detail := 'pas encore implementee';
            ELSE
                v_statut := 'PASS'; v_detail := SQLERRM;
            END IF;
        WHEN OTHERS THEN v_statut := 'WARN'; v_detail := 'erreur systeme brute : ' || SQLERRM;
    END;
    INSERT INTO test_results(test, statut, detail) VALUES (p_test, v_statut, v_detail);
END $$;

-- t_info : cas ambigu, on constate sans juger
CREATE OR REPLACE FUNCTION pg_temp.t_info(p_test TEXT, p_sql TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_detail TEXT := 'accepte';
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION 'rollback_test' USING ERRCODE = 'ZZ001';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN NULL;
        WHEN OTHERS THEN v_detail := 'refuse : ' || SQLERRM;
    END;
    INSERT INTO test_results(test, statut, detail) VALUES (p_test, 'INFO', v_detail);
END $$;


DO $main$
BEGIN

/* ------------------------------ ajouter_auteur ----------------------------- */
PERFORM pg_temp.t_ok('ajouter_auteur : insere l''auteur et renvoie son id',
$q$ DO $x$ DECLARE v INT;
   BEGIN
     v := ajouter_auteur('Test Auteur', 'France');
     IF v IS NULL OR NOT EXISTS (SELECT 1 FROM auteur WHERE id_auteur = v AND nom = 'Test Auteur' AND pays = 'France') THEN
       RAISE EXCEPTION 'auteur non insere ou id NULL';
     END IF;
   END $x$ $q$);
PERFORM pg_temp.t_err('ajouter_auteur : nom NULL refuse',   $q$ SELECT ajouter_auteur(NULL) $q$);
PERFORM pg_temp.t_err('ajouter_auteur : nom vide refuse',   $q$ SELECT ajouter_auteur('   ') $q$);
PERFORM pg_temp.t_err('ajouter_auteur : nom trop long (100 car.) -> message clair', $q$ SELECT ajouter_auteur(repeat('x', 100)) $q$);

/* ------------------------------ ajouter_livre ------------------------------ */
PERFORM pg_temp.t_ok('ajouter_livre : insere le livre et renvoie son id',
$q$ DO $x$ DECLARE v INT;
   BEGIN
     v := ajouter_livre('Livre Test', 6, 1, 2020, 2);
     IF v IS NULL OR NOT EXISTS (SELECT 1 FROM livre WHERE id_livre = v AND titre = 'Livre Test' AND nb_exemplaires = 2) THEN
       RAISE EXCEPTION 'livre non insere ou id NULL';
     END IF;
   END $x$ $q$);
PERFORM pg_temp.t_ok ('ajouter_livre : annee NULL accepte (colonne facultative)', $q$ SELECT ajouter_livre('Sans annee', 6, 1, NULL, 2) $q$);
PERFORM pg_temp.t_err('ajouter_livre : nb_exemplaires NULL refuse',   $q$ SELECT ajouter_livre('T', 6, 1, 2020, NULL) $q$);
PERFORM pg_temp.t_err('ajouter_livre : nb_exemplaires negatif refuse', $q$ SELECT ajouter_livre('T', 6, 1, 2020, -1) $q$);
PERFORM pg_temp.t_err('ajouter_livre : nb_exemplaires = 0 refuse (decision : strictement positif)', $q$ SELECT ajouter_livre('T', 6, 1, 2020, 0) $q$);
PERFORM pg_temp.t_err('ajouter_livre : auteur inexistant refuse',     $q$ SELECT ajouter_livre('T', 999, 1, 2020, 2) $q$);
PERFORM pg_temp.t_err('ajouter_livre : categorie inexistante refusee', $q$ SELECT ajouter_livre('T', 6, 999, 2020, 2) $q$);
PERFORM pg_temp.t_err('ajouter_livre : titre NULL refuse',            $q$ SELECT ajouter_livre(NULL, 6, 1, 2020, 2) $q$);
PERFORM pg_temp.t_err('ajouter_livre : titre vide refuse',            $q$ SELECT ajouter_livre('', 6, 1, 2020, 2) $q$);

/* ---------------------------- nb_livres_categorie -------------------------- */
PERFORM pg_temp.t_eq ('nb_livres_categorie(1) Roman = 4',     $q$ SELECT nb_livres_categorie(1) $q$, '4');
PERFORM pg_temp.t_eq ('nb_livres_categorie(2) Science = 2',   $q$ SELECT nb_livres_categorie(2) $q$, '2');
PERFORM pg_temp.t_eq ('nb_livres_categorie(3) Essai = 2',     $q$ SELECT nb_livres_categorie(3) $q$, '2');
PERFORM pg_temp.t_eq ('nb_livres_categorie(4) Histoire = 0 (existe, sans livre)', $q$ SELECT nb_livres_categorie(4) $q$, '0');
PERFORM pg_temp.t_eq ('nb_livres_categorie(5) Poesie = 0',    $q$ SELECT nb_livres_categorie(5) $q$, '0');
PERFORM pg_temp.t_err('nb_livres_categorie(999) : categorie inexistante', $q$ SELECT nb_livres_categorie(999) $q$);
PERFORM pg_temp.t_err('nb_livres_categorie(NULL) refuse',     $q$ SELECT nb_livres_categorie(NULL) $q$);

/* ------------------------------ maj_annee_livres --------------------------- */
PERFORM pg_temp.t_eq ('maj_annee_livres : 5 livres avant 2000', $q$ SELECT maj_annee_livres() $q$, '5');

/* ---------------------------- liste_livres_auteur -------------------------- */
PERFORM pg_temp.t_eq ('liste_livres_auteur(Victor Hugo) = 2 livres',  $q$ SELECT liste_livres_auteur('Victor Hugo') $q$, '2');
PERFORM pg_temp.t_eq ('liste_livres_auteur(Assia Djebar) = 0, sans erreur', $q$ SELECT liste_livres_auteur('Assia Djebar') $q$, '0');
PERFORM pg_temp.t_err('liste_livres_auteur : auteur inexistant', $q$ SELECT liste_livres_auteur('Inconnu') $q$);
PERFORM pg_temp.t_err('liste_livres_auteur : NULL refuse',        $q$ SELECT liste_livres_auteur(NULL) $q$);

/* ------------------------------ compter_elements --------------------------- */
PERFORM pg_temp.t_eq ('compter_elements(livre) = 8',       $q$ SELECT compter_elements('livre') $q$, '8');
PERFORM pg_temp.t_eq ('compter_elements(emprunt) = 6',     $q$ SELECT compter_elements('emprunt') $q$, '6');
PERFORM pg_temp.t_eq ('compter_elements(reservation) = 3', $q$ SELECT compter_elements('reservation') $q$, '3');
PERFORM pg_temp.t_eq ('compter_elements(auteur) = 6',      $q$ SELECT compter_elements('auteur') $q$, '6');
PERFORM pg_temp.t_err('compter_elements : table inexistante', $q$ SELECT compter_elements('table_inexistante') $q$);
PERFORM pg_temp.t_err('compter_elements : NULL refuse',       $q$ SELECT compter_elements(NULL) $q$);
PERFORM pg_temp.t_ok ('compter_elements : injection SQL sans effet (la table livre survit)',
$q$ DO $x$ BEGIN
     BEGIN PERFORM compter_elements('livre; DROP TABLE livre'); EXCEPTION WHEN OTHERS THEN NULL; END;
     IF to_regclass('livre') IS NULL THEN RAISE EXCEPTION 'la table livre a ete supprimee !'; END IF;
   END $x$ $q$);
PERFORM pg_temp.t_eq ('compter_elements(Livre) : majuscules acceptees (insensible a la casse)', $q$ SELECT compter_elements('Livre') $q$, '8');
PERFORM pg_temp.t_eq ('compter_elements(LIVRE) : majuscules acceptees', $q$ SELECT compter_elements('LIVRE') $q$, '8');

/* ---------------------------------- trigger -------------------------------- */
PERFORM pg_temp.t_eq ('trigger verif_disponibilite existe sur emprunt',
    $q$ SELECT count(*) FROM pg_trigger WHERE tgname = 'verif_disponibilite' AND NOT tgisinternal $q$, '1');
PERFORM pg_temp.t_err('trigger : livre 3 Fondation (2 ex., 2 empruntes) refuse', $q$ INSERT INTO emprunt(id_livre, id_emprunteur) VALUES (3, 4) $q$);
PERFORM pg_temp.t_err('trigger : livre 4 Les Robots (0 exemplaire) refuse',     $q$ INSERT INTO emprunt(id_livre, id_emprunteur) VALUES (4, 4) $q$);
PERFORM pg_temp.t_err('trigger : livre 999 inexistant -> message clair',        $q$ INSERT INTO emprunt(id_livre, id_emprunteur) VALUES (999, 4) $q$);
PERFORM pg_temp.t_ok ('trigger : livre 1 Miserables (2 restants) accepte',      $q$ INSERT INTO emprunt(id_livre, id_emprunteur) VALUES (1, 4) $q$);
PERFORM pg_temp.t_err('trigger : livre 5 (1 exemplaire), 2e emprunt refuse',
$q$ DO $x$ BEGIN
     INSERT INTO emprunt(id_livre, id_emprunteur) VALUES (5, 1);
     INSERT INTO emprunt(id_livre, id_emprunteur) VALUES (5, 2);
   END $x$ $q$);
PERFORM pg_temp.t_err('trigger : insertion multi-lignes sur livre 5 refusee',
    $q$ INSERT INTO emprunt(id_livre, id_emprunteur) SELECT 5, id_emprunteur FROM emprunteur WHERE id_emprunteur IN (1, 2) $q$);
PERFORM pg_temp.t_ok ('trigger : emprunt deja rendu a l''insertion accepte (livre 3)',
    $q$ INSERT INTO emprunt(id_livre, id_emprunteur, date_emprunt, date_retour) VALUES (3, 4, '2026-01-01', '2026-01-10') $q$);
PERFORM pg_temp.t_ok ('trigger : UPDATE (rendre un livre) jamais bloque',
    $q$ UPDATE emprunt SET date_retour = CURRENT_DATE WHERE id_emprunt = 1 $q$);
PERFORM pg_temp.t_ok ('trigger : apres un retour, livre 3 redevient empruntable',
$q$ DO $x$ BEGIN
     UPDATE emprunt SET date_retour = CURRENT_DATE WHERE id_emprunt = 1;
     INSERT INTO emprunt(id_livre, id_emprunteur) VALUES (3, 4);
   END $x$ $q$);

END $main$;

/* ---------------------------------- RESULTATS ------------------------------ */
SELECT statut, count(*) AS nb FROM test_results GROUP BY statut ORDER BY statut;
SELECT n, statut, test, detail FROM test_results ORDER BY n;