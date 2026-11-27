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

/* --------------------------- exemplaires_disponibles ----------------------- */
PERFORM pg_temp.t_eq ('exemplaires_disponibles(1) Miserables = 2',  $q$ SELECT exemplaires_disponibles(1) $q$, '2');
PERFORM pg_temp.t_eq ('exemplaires_disponibles(3) Fondation = 0 (2 ex., 2 empruntes)', $q$ SELECT exemplaires_disponibles(3) $q$, '0');
PERFORM pg_temp.t_eq ('exemplaires_disponibles(4) Les Robots = 0 (0 exemplaire)', $q$ SELECT exemplaires_disponibles(4) $q$, '0');
PERFORM pg_temp.t_eq ('exemplaires_disponibles(5) = 1',             $q$ SELECT exemplaires_disponibles(5) $q$, '1');
PERFORM pg_temp.t_eq ('exemplaires_disponibles(8) = 1',             $q$ SELECT exemplaires_disponibles(8) $q$, '1');
PERFORM pg_temp.t_err('exemplaires_disponibles(999) : livre inexistant', $q$ SELECT exemplaires_disponibles(999) $q$);
PERFORM pg_temp.t_err('exemplaires_disponibles(NULL) refuse',       $q$ SELECT exemplaires_disponibles(NULL) $q$);

/* ------------------------------ emprunter_livre ---------------------------- */
PERFORM pg_temp.t_ok ('emprunter_livre : insere l''emprunt et renvoie son id',
$q$ DO $x$ DECLARE v INT;
   BEGIN
     v := emprunter_livre(1, 4);
     IF v IS NULL OR NOT EXISTS (SELECT 1 FROM emprunt WHERE id_emprunt = v AND id_livre = 1 AND id_emprunteur = 4 AND date_retour IS NULL) THEN
       RAISE EXCEPTION 'emprunt non insere ou id NULL';
     END IF;
   END $x$ $q$);
PERFORM pg_temp.t_err('emprunter_livre : livre 3 sans exemplaire disponible', $q$ SELECT emprunter_livre(3, 4) $q$);
PERFORM pg_temp.t_err('emprunter_livre : livre 4 (0 exemplaire)',             $q$ SELECT emprunter_livre(4, 4) $q$);
PERFORM pg_temp.t_err('emprunter_livre : livre inexistant',                   $q$ SELECT emprunter_livre(999, 4) $q$);
PERFORM pg_temp.t_err('emprunter_livre : emprunteur inexistant',              $q$ SELECT emprunter_livre(1, 999) $q$);
PERFORM pg_temp.t_err('emprunter_livre : livre NULL refuse',                  $q$ SELECT emprunter_livre(NULL, 4) $q$);
PERFORM pg_temp.t_err('emprunter_livre : emprunteur NULL refuse',             $q$ SELECT emprunter_livre(1, NULL) $q$);
PERFORM pg_temp.t_err('emprunter_livre : livre 5 (1 ex.), 2e emprunt refuse',
$q$ DO $x$ BEGIN PERFORM emprunter_livre(5, 1); PERFORM emprunter_livre(5, 2); END $x$ $q$);

/* -------------------------------- rendre_livre ----------------------------- */
PERFORM pg_temp.t_eq ('rendre_livre(1) renvoie la date du jour', $q$ SELECT rendre_livre(1) = CURRENT_DATE $q$, 'true');
PERFORM pg_temp.t_ok ('rendre_livre : date_retour renseignee et exemplaire libere',
$q$ DO $x$ BEGIN
     PERFORM rendre_livre(1);
     IF (SELECT date_retour FROM emprunt WHERE id_emprunt = 1) IS NULL THEN RAISE EXCEPTION 'date_retour non renseignee'; END IF;
     IF exemplaires_disponibles(3) <> 1 THEN RAISE EXCEPTION 'exemplaire non libere'; END IF;
   END $x$ $q$);
PERFORM pg_temp.t_err('rendre_livre : emprunt 4 deja rendu',  $q$ SELECT rendre_livre(4) $q$);
PERFORM pg_temp.t_err('rendre_livre : emprunt inexistant',    $q$ SELECT rendre_livre(999) $q$);
PERFORM pg_temp.t_err('rendre_livre : NULL refuse',           $q$ SELECT rendre_livre(NULL) $q$);
PERFORM pg_temp.t_err('rendre_livre : emprunt date dans le futur -> message clair',
$q$ DO $x$ DECLARE v INT;
   BEGIN
     INSERT INTO emprunt(id_livre, id_emprunteur, date_emprunt) VALUES (8, 1, CURRENT_DATE + 5) RETURNING id_emprunt INTO v;
     PERFORM rendre_livre(v);
   END $x$ $q$);

/* ----------------------------- emprunts_en_retard -------------------------- */
PERFORM pg_temp.t_eq ('emprunts_en_retard(0) = nb d''emprunts en cours ouverts avant aujourd''hui',
    $q$ SELECT emprunts_en_retard(0) = (SELECT count(*) FROM emprunt WHERE date_retour IS NULL AND date_emprunt < CURRENT_DATE) $q$, 'true');
PERFORM pg_temp.t_eq ('emprunts_en_retard(100000) = 0, sans erreur', $q$ SELECT emprunts_en_retard(100000) $q$, '0');
PERFORM pg_temp.t_ok ('emprunts_en_retard() : valeur par defaut acceptee', $q$ SELECT emprunts_en_retard() $q$);
PERFORM pg_temp.t_err('emprunts_en_retard(-1) refuse',  $q$ SELECT emprunts_en_retard(-1) $q$);
PERFORM pg_temp.t_err('emprunts_en_retard(NULL) refuse', $q$ SELECT emprunts_en_retard(NULL) $q$);

/* ------------------------------ file_attente_livre ------------------------- */
PERFORM pg_temp.t_eq ('file_attente_livre(3) : 1 reservation en attente', $q$ SELECT count(*) FROM file_attente_livre(3) $q$, '1');
PERFORM pg_temp.t_eq ('file_attente_livre(1) : reservation validee exclue', $q$ SELECT count(*) FROM file_attente_livre(1) $q$, '0');
PERFORM pg_temp.t_eq ('file_attente_livre(6) : reservation annulee exclue', $q$ SELECT count(*) FROM file_attente_livre(6) $q$, '0');
PERFORM pg_temp.t_eq ('file_attente_livre(4) : livre existant sans reservation = 0', $q$ SELECT count(*) FROM file_attente_livre(4) $q$, '0');
PERFORM pg_temp.t_ok ('file_attente_livre : rangs dans l''ordre d''arrivee',
$q$ DO $x$ BEGIN
     INSERT INTO reservation(id_livre, id_emprunteur, date_reservation, statut) VALUES (3, 4, '2026-10-05', 'en attente');
     IF (SELECT rang FROM file_attente_livre(3) WHERE nom_emprunteur = 'Sophie Nguyen') <> 1 THEN RAISE EXCEPTION 'Sophie devrait etre 1re'; END IF;
     IF (SELECT rang FROM file_attente_livre(3) WHERE nom_emprunteur = 'Thomas Dubois') <> 2 THEN RAISE EXCEPTION 'Thomas devrait etre 2e'; END IF;
   END $x$ $q$);
PERFORM pg_temp.t_err('file_attente_livre(999) : livre inexistant', $q$ SELECT * FROM file_attente_livre(999) $q$);
PERFORM pg_temp.t_err('file_attente_livre(NULL) refuse',            $q$ SELECT * FROM file_attente_livre(NULL) $q$);

/* ------------------------------ rechercher_livres -------------------------- */
PERFORM pg_temp.t_eq ('rechercher_livres() sans filtre = 8 livres', $q$ SELECT count(*) FROM rechercher_livres() $q$, '8');
PERFORM pg_temp.t_eq ('rechercher_livres(''misérables'') insensible a la casse = 1', $q$ SELECT count(*) FROM rechercher_livres('misérables') $q$, '1');
PERFORM pg_temp.t_eq ('rechercher_livres(NULL, 1900) = 2 (Miserables, Notre-Dame)', $q$ SELECT count(*) FROM rechercher_livres(NULL, 1900) $q$, '2');
PERFORM pg_temp.t_eq ('rechercher_livres(''les'', 1900) = 1 (Les Miserables)', $q$ SELECT count(*) FROM rechercher_livres('les', 1900) $q$, '1');
PERFORM pg_temp.t_eq ('rechercher_livres(''zzz'') = 0, sans erreur', $q$ SELECT count(*) FROM rechercher_livres('zzz') $q$, '0');
PERFORM pg_temp.t_eq ('rechercher_livres(''%'') : joker echappe, cherche un % litteral', $q$ SELECT count(*) FROM rechercher_livres('%') $q$, '0');
PERFORM pg_temp.t_eq ('rechercher_livres : injection sans effet', $q$ SELECT count(*) FROM rechercher_livres($z$' OR 1=1 --$z$) $q$, '0');
PERFORM pg_temp.t_err('rechercher_livres : mot vide refuse', $q$ SELECT * FROM rechercher_livres('  ') $q$);

/* ------------------------------ repartition_livres ------------------------- */
PERFORM pg_temp.t_eq ('repartition_livres(id_categorie) : 3 categories utilisees', $q$ SELECT count(*) FROM repartition_livres('id_categorie') $q$, '3');
PERFORM pg_temp.t_eq ('repartition_livres(id_categorie) : Roman (1) = 4 livres', $q$ SELECT nb_livres FROM repartition_livres('id_categorie') WHERE valeur = '1' $q$, '4');
PERFORM pg_temp.t_eq ('repartition_livres(id_auteur) : Hugo (1) = 2 livres', $q$ SELECT nb_livres FROM repartition_livres('id_auteur') WHERE valeur = '1' $q$, '2');
PERFORM pg_temp.t_eq ('repartition_livres(ANNEE) : majuscules acceptees, 8 annees', $q$ SELECT count(*) FROM repartition_livres('ANNEE') $q$, '8');
PERFORM pg_temp.t_err('repartition_livres : colonne inexistante', $q$ SELECT * FROM repartition_livres('couleur') $q$);
PERFORM pg_temp.t_err('repartition_livres : NULL refuse',          $q$ SELECT * FROM repartition_livres(NULL) $q$);
PERFORM pg_temp.t_err('repartition_livres : colonne d''une autre table refusee', $q$ SELECT * FROM repartition_livres('pays') $q$);
PERFORM pg_temp.t_ok ('repartition_livres : injection sans effet (la table livre survit)',
$q$ DO $x$ BEGIN
     BEGIN PERFORM repartition_livres('annee FROM livre; DROP TABLE livre; --'); EXCEPTION WHEN OTHERS THEN NULL; END;
     IF to_regclass('livre') IS NULL THEN RAISE EXCEPTION 'la table livre a ete supprimee !'; END IF;
   END $x$ $q$);

/* ---------------------------------- trigger -------------------------------- */
PERFORM pg_temp.t_eq ('trigger valider_reservation_retour existe sur emprunt',
    $q$ SELECT count(*) FROM pg_trigger WHERE tgname = 'valider_reservation_retour' AND NOT tgisinternal $q$, '1');
PERFORM pg_temp.t_ok ('trigger : retour de Fondation -> reservation 1 en attente devient validee',
$q$ DO $x$ BEGIN
     UPDATE emprunt SET date_retour = CURRENT_DATE WHERE id_emprunt = 1;
     IF (SELECT statut FROM reservation WHERE id_reservation = 1) <> 'validée' THEN RAISE EXCEPTION 'reservation 1 non validee'; END IF;
   END $x$ $q$);
PERFORM pg_temp.t_ok ('trigger : via rendre_livre, meme resultat',
$q$ DO $x$ BEGIN
     PERFORM rendre_livre(2);
     IF (SELECT statut FROM reservation WHERE id_reservation = 1) <> 'validée' THEN RAISE EXCEPTION 'reservation 1 non validee'; END IF;
   END $x$ $q$);
PERFORM pg_temp.t_ok ('trigger : une seule reservation validee par retour, la plus ancienne d''abord',
$q$ DO $x$ BEGIN
     INSERT INTO reservation(id_livre, id_emprunteur, date_reservation, statut) VALUES (3, 4, '2026-10-05', 'en attente');
     UPDATE emprunt SET date_retour = CURRENT_DATE WHERE id_emprunt = 1;
     IF (SELECT statut FROM reservation WHERE id_reservation = 1) <> 'validée' THEN RAISE EXCEPTION 'la plus ancienne devait etre validee'; END IF;
     IF (SELECT count(*) FROM reservation WHERE id_livre = 3 AND statut = 'en attente') <> 1 THEN RAISE EXCEPTION 'la 2e reservation devait rester en attente'; END IF;
   END $x$ $q$);
PERFORM pg_temp.t_ok ('trigger : retour sans reservation en attente -> rien ne change (livre 1)',
$q$ DO $x$ BEGIN
     UPDATE emprunt SET date_retour = CURRENT_DATE WHERE id_emprunt = 3;
     IF (SELECT count(*) FROM reservation WHERE statut = 'validée') <> 1 THEN RAISE EXCEPTION 'une reservation a change de statut'; END IF;
   END $x$ $q$);
PERFORM pg_temp.t_ok ('trigger : une reservation annulee n''est jamais reactivee (livre 6)',
$q$ DO $x$ DECLARE v INT;
   BEGIN
     v := emprunter_livre(6, 1);
     PERFORM rendre_livre(v);
     IF (SELECT statut FROM reservation WHERE id_reservation = 3) <> 'annulée' THEN RAISE EXCEPTION 'reservation annulee reactivee'; END IF;
   END $x$ $q$);
PERFORM pg_temp.t_ok ('trigger : modification sans retour (date_retour deja renseignee) ignoree',
$q$ DO $x$ BEGIN
     INSERT INTO reservation(id_livre, id_emprunteur, date_reservation, statut) VALUES (1, 1, '2026-10-20', 'en attente');
     UPDATE emprunt SET date_retour = '2025-06-25' WHERE id_emprunt = 4;
     IF (SELECT statut FROM reservation WHERE id_livre = 1 AND id_emprunteur = 1) <> 'en attente' THEN RAISE EXCEPTION 'declenchement a tort'; END IF;
   END $x$ $q$);

END $main$;

/* ---------------------------------- RESULTATS ------------------------------ */
SELECT statut, count(*) AS nb FROM test_results GROUP BY statut ORDER BY statut;
SELECT n, statut, test, detail FROM test_results ORDER BY n;