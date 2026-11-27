/* ============================================================================
    Projet PL/pgSQL - Bibliotheque+  (M1 Informatique - Lyon 2, 2026-2027)
   PARTIE 1 : fonctions et trigger guides
   Binome : Zakaria Boutarfa / Chahid Lafdel
Prerequis : bibliotheque_plus.sql execute une fois.
Conventions de noms utilisés: parametres = p_..., variables = v_..., curseurs = cur_...
 */ 

CREATE OR REPLACE FUNCTION ajouter_auteur(p_nom TEXT, p_pays TEXT DEFAULT NULL)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE											
    v_id INT;
BEGIN
    IF p_nom IS NULL or btrim(p_nom) ='' THEN				-- Si nom d'auteur NULL ou chaîne comportant des espaces (qu'on enlève avec btrim()) on lève une exception.
        RAISE EXCEPTION 'ajouter_auteur : le nom de l''auteur est obligatoire';
    END IF;
	IF length(btrim(p_nom)) > 60 THEN
        RAISE EXCEPTION 'ajouter_auteur : nom trop long (% caracteres, maximum 60)',	--Choix arbitraire de nom avec 60 characters, pour éviter les 
                        length(btrim(p_nom));
    END IF;

    INSERT INTO auteur (nom, pays)	--Si p_nom valid insertion et retourne l'auteur id de la nouvelle entrée
    VALUES (btrim(p_nom), p_pays)
    RETURNING id_auteur INTO v_id;
    RETURN v_id;
END;
$$;


/* ----------------------------------------------------------------------------
 Dans la fonction ajouter_livre nb_exemplaires doit etre >= 1 (un livre sans exemplaire n'est pas
   ajoute, meme si le CHECK de la table accepte 0).
   ---------------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION ajouter_livre(
    p_titre          TEXT,
    p_id_auteur      INT,
    p_id_categorie   INT,
    p_annee          INT,
    p_nb_exemplaires INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    IF p_titre IS NULL OR btrim(p_titre) = '' THEN
        RAISE EXCEPTION 'ajouter_livre : le titre est obligatoire';	--Nettoyage d'entrées NULL ou vides
    END IF;

   
    IF p_nb_exemplaires IS NULL THEN
        RAISE EXCEPTION 'ajouter_livre : le nombre d''exemplaires est obligatoire';
    END IF;

    IF p_nb_exemplaires < 1 THEN
        RAISE EXCEPTION 'ajouter_livre : le nombre d''exemplaires doit etre positif (recu : %)',
                        p_nb_exemplaires;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auteur WHERE id_auteur = p_id_auteur) THEN
        RAISE EXCEPTION 'ajouter_livre : auteur inexistant (id_auteur = %)', p_id_auteur;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM categorie WHERE id_categorie = p_id_categorie) THEN
        RAISE EXCEPTION 'ajouter_livre : categorie inexistante (id_categorie = %)', p_id_categorie;
    END IF;

    INSERT INTO livre (titre, id_auteur, id_categorie, annee, nb_exemplaires)
    VALUES (btrim(p_titre), p_id_auteur, p_id_categorie, p_annee, p_nb_exemplaires) /* On valide l'ajout d'un live, on 
															n'insère que si le titre du livre est valide, le nombres d'éxemplaires non null et cohérent, et que l'auteur et la catégorie existent */ 
    RETURNING id_livre INTO v_id;

    RETURN v_id;
END;
$$;



CREATE OR REPLACE FUNCTION nb_livres_categorie(p_id_categorie INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_nb INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM categorie WHERE id_categorie = p_id_categorie) THEN
        RAISE EXCEPTION 'nb_livres_categorie : categorie inexistante (id_categorie = %)',
                        p_id_categorie;
    END IF;

    SELECT count(*) INTO v_nb -- le nombres de livres dans une catégories et non le nombre d'exemplaires
    FROM livre
    WHERE id_categorie = p_id_categorie;

    RETURN v_nb;
END;
$$;



CREATE OR REPLACE FUNCTION maj_annee_livres()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    enregistrement  RECORD; 	-- variable qui recoit chaque ligne du SELECT (titre, annee)
    v_nb INT := 0;
BEGIN
	-- curseur implicite : PostgreSQL ouvre, lit et ferme le curseur.
    FOR enregistrement IN
        SELECT titre, annee
        FROM   livre
        WHERE  annee < 2000
        ORDER  BY annee, titre
    LOOP
        RAISE NOTICE '% (%)', enregistrement.titre, enregistrement.annee;	-- Simple affichage de message (non error)
        v_nb := v_nb + 1;
    END LOOP;

    RETURN v_nb;
END;
$$;



CREATE OR REPLACE FUNCTION liste_livres_auteur(p_nom_auteur TEXT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    cur_livres CURSOR (c_nom TEXT) FOR
        SELECT l.titre, l.annee
        FROM   livre l
        JOIN   auteur a ON a.id_auteur = l.id_auteur
        WHERE  a.nom = c_nom
        ORDER  BY l.annee, l.titre;
    rec  RECORD;
    v_nb INT := 0;
BEGIN
    IF p_nom_auteur IS NULL OR btrim(p_nom_auteur) = '' THEN
        RAISE EXCEPTION 'liste_livres_auteur : le nom de lauteur est obligatoire';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auteur WHERE nom = p_nom_auteur) THEN
        RAISE EXCEPTION 'liste_livres_auteur : auteur inexistant (%)', p_nom_auteur;
    END IF;

    OPEN cur_livres(p_nom_auteur);
    LOOP
        FETCH cur_livres INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE '% (%)', rec.titre, rec.annee;
        v_nb := v_nb + 1;
    END LOOP;
    CLOSE cur_livres;

    IF v_nb = 0 THEN
        RAISE NOTICE 'liste_livres_auteur : % n a aucun livre', p_nom_auteur;
    END IF;

    RETURN v_nb;
END;
$$;

CREATE OR REPLACE FUNCTION compter_elements(p_table_name TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_table TEXT;
    v_nb    BIGINT;
BEGIN
    IF p_table_name IS NULL OR btrim(p_table_name) = '' THEN
        RAISE EXCEPTION 'compter_elements : le nom de la table est obligatoire';
    END IF;

    -- SQL met en minuscules les noms non quotes (FROM Livre = FROM livre) :
    -- on reproduit ce comportement pour que 'Livre' et 'LIVRE' fonctionnent
    v_table := lower(btrim(p_table_name));
	-- to_regclass renvoie NULL si la table n'existe pas : message clair au lieu d'une erreur systeme
    IF to_regclass(format('%I', v_table)) IS NULL THEN
        RAISE EXCEPTION 'compter_elements : la table "%" n''existe pas', p_table_name;
    END IF;
	-- SQL dynamique : %I met le nom entre guillemets ce qui protège contre les injections.
    EXECUTE format('SELECT count(*) FROM %I', v_table) INTO v_nb;

    RETURN v_nb;
END;
$$;
/* Refuse l'insertion d'un emprunt en cours quand le livre n'a plus d'exemplaire
   disponible, au sens du sujet : nb_exemplaires - (emprunts en cours) >= 1,
   un emprunt etant en cours quand date_retour IS NULL.
   Un trigger = 2 morceaux : la fonction (RETURNS TRIGGER) puis CREATE TRIGGER.
   Limite connue : seul l'INSERT est controle (voir rapport). */	

CREATE OR REPLACE FUNCTION trg_verif_disponibilite()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_total    INT;
    v_en_cours INT;
BEGIN
    -- Emprunt deja rendu a l'insertion (donnee historique) : il n'occupe aucun exemplaire
    IF NEW.date_retour IS NOT NULL THEN
        RETURN NEW;
    END IF;

    
    SELECT nb_exemplaires INTO v_total
    FROM   livre
    WHERE  id_livre = NEW.id_livre
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'verif_disponibilite : livre inexistant (id_livre = %)', NEW.id_livre;
    END IF;

    SELECT count(*) INTO v_en_cours
    FROM   emprunt
    WHERE  id_livre = NEW.id_livre
      AND  date_retour IS NULL;

    IF v_total - v_en_cours < 1 THEN
        RAISE EXCEPTION 'verif_disponibilite : plus d''exemplaire disponible pour le livre % (% exemplaire(s), % emprunt(s) en cours)',
                        NEW.id_livre, v_total, v_en_cours;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS verif_disponibilite ON emprunt;
CREATE TRIGGER verif_disponibilite
    BEFORE INSERT ON emprunt
    FOR EACH ROW
    EXECUTE FUNCTION trg_verif_disponibilite();
