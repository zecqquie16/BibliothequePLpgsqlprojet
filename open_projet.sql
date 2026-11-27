/* ============================================================================
   Projet PL/pgSQL - Bibliotheque+  (M1 Informatique - Lyon 2, 2026-2027)
   PARTIE 2 : fonctions et trigger ouverts

   Prerequis : bibliotheque_plus.sql puis guided_projet.sql executes une fois.
   (valider_reservation_retour s'appuie sur la definition de disponibilite
    du sujet : nb_exemplaires - emprunts en cours >= 1)

   Contenu :
     1. exemplaires_disponibles(id_livre)   classique (requete)
     2. emprunter_livre(id_livre, id_emp)   classique (insertion)
     3. rendre_livre(id_emprunt)            classique (mise a jour)
     4. emprunts_en_retard(jours)           curseur IMPLICITE
     5. file_attente_livre(id_livre)        curseur EXPLICITE
     6. rechercher_livres(mot, annee_max)   SQL PARAMETRE (EXECUTE ... USING)
     7. repartition_livres(colonne)         SQL DYNAMIQUE justifie (format %I)
     8. trigger valider_reservation_retour  validation auto des reservations
   ============================================================================ */


/* ----------------------------------------------------------------------------
   1. exemplaires_disponibles(p_id_livre)
   Nombre d'exemplaires encore empruntables : total - emprunts en cours.
   GREATEST(..., 0) : si les donnees sont incoherentes (plus d'emprunts en cours
   que d'exemplaires), on renvoie 0 plutot qu'un nombre negatif.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION exemplaires_disponibles(p_id_livre INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_total    INT;
    v_en_cours INT;
BEGIN
    IF p_id_livre IS NULL THEN
        RAISE EXCEPTION 'exemplaires_disponibles : l''identifiant du livre est obligatoire';
    END IF;

    SELECT nb_exemplaires INTO v_total
    FROM   livre
    WHERE  id_livre = p_id_livre;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'exemplaires_disponibles : livre inexistant (id_livre = %)', p_id_livre;
    END IF;

    SELECT count(*) INTO v_en_cours
    FROM   emprunt
    WHERE  id_livre = p_id_livre
      AND  date_retour IS NULL;

    RETURN GREATEST(v_total - v_en_cours, 0);
END;
$$;


/* ----------------------------------------------------------------------------
   2. emprunter_livre(p_id_livre, p_id_emprunteur)
   Enregistre un emprunt a la date du jour et renvoie son identifiant.
   Les verifications donnent des messages clairs ; le trigger verif_disponibilite
   (partie 1) reste le garde-fou final sur la table.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION emprunter_livre(p_id_livre INT, p_id_emprunteur INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    IF p_id_livre IS NULL OR p_id_emprunteur IS NULL THEN
        RAISE EXCEPTION 'emprunter_livre : le livre et l''emprunteur sont obligatoires';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM emprunteur WHERE id_emprunteur = p_id_emprunteur) THEN
        RAISE EXCEPTION 'emprunter_livre : emprunteur inexistant (id_emprunteur = %)', p_id_emprunteur;
    END IF;

    -- leve deja une exception claire si le livre n'existe pas
    IF exemplaires_disponibles(p_id_livre) < 1 THEN
        RAISE EXCEPTION 'emprunter_livre : aucun exemplaire disponible pour le livre %', p_id_livre;
    END IF;

    INSERT INTO emprunt (id_livre, id_emprunteur)
    VALUES (p_id_livre, p_id_emprunteur)
    RETURNING id_emprunt INTO v_id;

    RETURN v_id;
END;
$$;


/* ----------------------------------------------------------------------------
   3. rendre_livre(p_id_emprunt)
   Enregistre le retour d'un emprunt en cours (date_retour = aujourd'hui) et
   renvoie la date de retour. Cet UPDATE declenche le trigger
   valider_reservation_retour (voir plus bas).
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION rendre_livre(p_id_emprunt INT)
RETURNS DATE
LANGUAGE plpgsql
AS $$
DECLARE
    v_date_emprunt DATE;
    v_date_retour  DATE;
BEGIN
    IF p_id_emprunt IS NULL THEN
        RAISE EXCEPTION 'rendre_livre : l''identifiant de l''emprunt est obligatoire';
    END IF;

    SELECT date_emprunt, date_retour INTO v_date_emprunt, v_date_retour
    FROM   emprunt
    WHERE  id_emprunt = p_id_emprunt
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'rendre_livre : emprunt inexistant (id_emprunt = %)', p_id_emprunt;
    END IF;

    IF v_date_retour IS NOT NULL THEN
        RAISE EXCEPTION 'rendre_livre : l''emprunt % est deja rendu (le %)', p_id_emprunt, v_date_retour;
    END IF;

    -- evite une violation brute de la contrainte chk_dates
    IF v_date_emprunt > CURRENT_DATE THEN
        RAISE EXCEPTION 'rendre_livre : l''emprunt % est date dans le futur (%)', p_id_emprunt, v_date_emprunt;
    END IF;

    UPDATE emprunt
    SET    date_retour = CURRENT_DATE
    WHERE  id_emprunt = p_id_emprunt;

    RETURN CURRENT_DATE;
END;
$$;


/* ----------------------------------------------------------------------------
   4. emprunts_en_retard(p_jours)   -- CURSEUR IMPLICITE
   Affiche (RAISE NOTICE) les emprunts en cours depuis plus de p_jours jours et
   renvoie leur nombre. Parcours de toute la requete : curseur implicite
   FOR ... IN requete LOOP.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION emprunts_en_retard(p_jours INT DEFAULT 21)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    enregistrement RECORD;
    v_nb           INT := 0;
BEGIN
    IF p_jours IS NULL OR p_jours < 0 THEN
        RAISE EXCEPTION 'emprunts_en_retard : le nombre de jours doit etre positif ou nul (recu : %)',
                        coalesce(p_jours::TEXT, 'NULL');
    END IF;

    FOR enregistrement IN
        SELECT e.id_emprunt, l.titre, em.nom, e.date_emprunt,
               CURRENT_DATE - e.date_emprunt AS nb_jours
        FROM   emprunt e
        JOIN   livre l       ON l.id_livre = e.id_livre
        JOIN   emprunteur em ON em.id_emprunteur = e.id_emprunteur
        WHERE  e.date_retour IS NULL
          AND  CURRENT_DATE - e.date_emprunt > p_jours
        ORDER  BY e.date_emprunt, e.id_emprunt
    LOOP
        RAISE NOTICE 'Emprunt % : "%" emprunte par % depuis % jours (le %)',
                     enregistrement.id_emprunt, enregistrement.titre, enregistrement.nom,
                     enregistrement.nb_jours, enregistrement.date_emprunt;
        v_nb := v_nb + 1;
    END LOOP;

    IF v_nb = 0 THEN
        RAISE NOTICE 'emprunts_en_retard : aucun emprunt en cours depuis plus de % jours', p_jours;
    END IF;

    RETURN v_nb;
END;
$$;


/* ----------------------------------------------------------------------------
   5. file_attente_livre(p_id_livre)   -- CURSEUR EXPLICITE
   Liste les reservations « en attente » d'un livre, de la plus ancienne a la
   plus recente, avec leur rang dans la file. Curseur parametre : OPEN, FETCH
   dans une boucle, CLOSE.
   Colonnes de sortie prefixees (id_resa, date_resa...) pour ne pas entrer en
   conflit avec les colonnes des tables.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION file_attente_livre(p_id_livre INT)
RETURNS TABLE (rang INT, id_resa INT, nom_emprunteur TEXT, date_resa DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    cur_attente CURSOR (c_id_livre INT) FOR
        SELECT r.id_reservation, em.nom, r.date_reservation
        FROM   reservation r
        JOIN   emprunteur em ON em.id_emprunteur = r.id_emprunteur
        WHERE  r.id_livre = c_id_livre
          AND  r.statut = 'en attente'
        ORDER  BY r.date_reservation, r.id_reservation;
    rec     RECORD;
    v_rang  INT := 0;
BEGIN
    IF p_id_livre IS NULL THEN
        RAISE EXCEPTION 'file_attente_livre : l''identifiant du livre est obligatoire';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM livre WHERE id_livre = p_id_livre) THEN
        RAISE EXCEPTION 'file_attente_livre : livre inexistant (id_livre = %)', p_id_livre;
    END IF;

    OPEN cur_attente(p_id_livre);
    LOOP
        FETCH cur_attente INTO rec;
        EXIT WHEN NOT FOUND;
        v_rang         := v_rang + 1;
        rang           := v_rang;
        id_resa        := rec.id_reservation;
        nom_emprunteur := rec.nom;
        date_resa      := rec.date_reservation;
        RETURN NEXT;
    END LOOP;
    CLOSE cur_attente;

    RETURN;
END;
$$;


/* ----------------------------------------------------------------------------
   6. rechercher_livres(p_mot, p_annee_max)   -- SQL PARAMETRE
   Recherche multicritere (les deux filtres sont facultatifs : NULL = pas de
   filtre). La requete est executee avec EXECUTE ... USING : les valeurs
   transitent par les parametres $1 et $2, jamais par concatenation.
   Le motif de recherche est echappe (%, _ et \) pour que « 100% » soit cherche
   litteralement et non comme un joker.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION rechercher_livres(p_mot TEXT DEFAULT NULL, p_annee_max INT DEFAULT NULL)
RETURNS TABLE (id_livre INT, titre TEXT, nom_auteur TEXT, annee INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_motif TEXT;
    v_sql   TEXT;
BEGIN
    IF p_mot IS NOT NULL AND btrim(p_mot) = '' THEN
        RAISE EXCEPTION 'rechercher_livres : le mot recherche ne peut pas etre vide (utiliser NULL pour ne pas filtrer)';
    END IF;

    IF p_mot IS NOT NULL THEN
        v_motif := '%' || replace(replace(replace(btrim(p_mot), '\', '\\'), '%', '\%'), '_', '\_') || '%';
    END IF;

    v_sql := 'SELECT l.id_livre, l.titre::TEXT, a.nom::TEXT, l.annee
              FROM   livre l
              JOIN   auteur a ON a.id_auteur = l.id_auteur
              WHERE  ($1 IS NULL OR l.titre ILIKE $1)
                AND  ($2 IS NULL OR l.annee <= $2)
              ORDER  BY l.annee, l.titre';

    RETURN QUERY EXECUTE v_sql USING v_motif, p_annee_max;
END;
$$;


/* ----------------------------------------------------------------------------
   7. repartition_livres(p_colonne)   -- SQL DYNAMIQUE justifie
   Compte les livres par valeur de la colonne de livre passee en parametre
   (annee, id_categorie, id_auteur, nb_exemplaires...).
   Pourquoi du SQL dynamique : un NOM DE COLONNE ne peut pas etre un parametre
   ($1) d'une requete preparee ; seule une valeur le peut. La requete doit donc
   etre construite en texte puis executee.
   Securite : (1) la colonne doit exister dans livre (verifie dans pg_attribute),
   (2) l'identifiant est insere avec format('%I'), qui le met entre guillemets.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION repartition_livres(p_colonne TEXT)
RETURNS TABLE (valeur TEXT, nb_livres BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_col TEXT;
BEGIN
    IF p_colonne IS NULL OR btrim(p_colonne) = '' THEN
        RAISE EXCEPTION 'repartition_livres : le nom de la colonne est obligatoire';
    END IF;

    -- comme SQL pour les noms non quotes : 'Annee' et 'ANNEE' fonctionnent
    v_col := lower(btrim(p_colonne));

    IF NOT EXISTS (SELECT 1
                   FROM   pg_attribute
                   WHERE  attrelid = 'livre'::regclass
                     AND  attname  = v_col
                     AND  attnum   > 0
                     AND  NOT attisdropped) THEN
        RAISE EXCEPTION 'repartition_livres : la table livre n''a pas de colonne "%"', p_colonne;
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT %I::TEXT, count(*) FROM livre GROUP BY %I ORDER BY %I',
        v_col, v_col, v_col);
END;
$$;


/* ----------------------------------------------------------------------------
   8. TRIGGER valider_reservation_retour
   Objectif : quand un exemplaire est rendu, la plus ancienne reservation
   « en attente » du livre passe automatiquement a « validee ».
   Fonctionnement :
     - AFTER UPDATE OF date_retour sur emprunt, FOR EACH ROW ;
     - clause WHEN : ne se declenche que si date_retour passe de NULL a une date
       (un vrai retour), pas pour une autre modification de la ligne ;
     - AFTER : l'UPDATE est deja visible, donc exemplaires_disponibles() compte
       bien l'exemplaire qui vient d'etre rendu ;
     - une seule reservation validee par retour (un exemplaire = un lecteur),
       dans l'ordre d'arrivee (date_reservation puis id_reservation) ;
     - les reservations annulees ou deja validees ne sont jamais touchees.
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION trg_valider_reservation_retour()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_resa INT;
BEGIN
    -- garde-fou (la clause WHEN du trigger filtre deja ce cas)
    IF OLD.date_retour IS NOT NULL OR NEW.date_retour IS NULL THEN
        RETURN NEW;
    END IF;

    IF exemplaires_disponibles(NEW.id_livre) < 1 THEN
        RETURN NEW;
    END IF;

    SELECT id_reservation INTO v_id_resa
    FROM   reservation
    WHERE  id_livre = NEW.id_livre
      AND  statut = 'en attente'
    ORDER  BY date_reservation, id_reservation
    LIMIT  1
    FOR UPDATE;

    IF FOUND THEN
        UPDATE reservation
        SET    statut = 'validée'
        WHERE  id_reservation = v_id_resa;

        RAISE NOTICE 'valider_reservation_retour : reservation % validee pour le livre %',
                     v_id_resa, NEW.id_livre;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS valider_reservation_retour ON emprunt;
CREATE TRIGGER valider_reservation_retour
    AFTER UPDATE OF date_retour ON emprunt
    FOR EACH ROW
    WHEN (OLD.date_retour IS NULL AND NEW.date_retour IS NOT NULL)
    EXECUTE FUNCTION trg_valider_reservation_retour();