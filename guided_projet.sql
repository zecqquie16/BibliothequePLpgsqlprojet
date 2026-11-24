/* ============================================================================
   Prerequis : bibliotheque_plus.sql execute une fois.
 */ 

CREATE OR REPLACE FUNCTION ajouter_auteur(p_nom TEXT, p_pays TEXT DEFAULT NULL)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id INT;
BEGIN
    IF p_nom IS NULL or btrim(p_nom) ='' THEN
        RAISE EXCEPTION 'ajouter_auteur : le nom de l''auteur est obligatoire';
    END IF;
	IF length(btrim(p_nom)) > 60 THEN
        RAISE EXCEPTION 'ajouter_auteur : nom trop long (% caracteres, maximum 60)',
                        length(btrim(p_nom));
    END IF;

    INSERT INTO auteur (nom, pays)
    VALUES (btrim(p_nom), p_pays)
    RETURNING id_auteur INTO v_id;
    RETURN v_id;
END;
$$;


/* ----------------------------------------------------------------------------
 
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
        RAISE EXCEPTION 'ajouter_livre : le titre est obligatoire';
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
    VALUES (btrim(p_titre), p_id_auteur, p_id_categorie, p_annee, p_nb_exemplaires)
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

    SELECT count(*) INTO v_nb
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
    enregistrement  RECORD;
    v_nb INT := 0;
BEGIN
    FOR enregistrement IN
        SELECT titre, annee
        FROM   livre
        WHERE  annee < 2000
        ORDER  BY annee, titre
    LOOP
        RAISE NOTICE '% (%)', enregistrement.titre, enregistrement.annee;
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

    IF to_regclass(format('%I', v_table)) IS NULL THEN
        RAISE EXCEPTION 'compter_elements : la table "%" n''existe pas', p_table_name;
    END IF;

    EXECUTE format('SELECT count(*) FROM %I', v_table) INTO v_nb;

    RETURN v_nb;
END;
$$;


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