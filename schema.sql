CREATE TABLE hasta (
	tc char(11) PRIMARY KEY,
	isim varchar(50) NOT NULL,
	soyisim varchar(50) NOT NULL,
	cinsiyet char(1) NOT NULL CHECK (cinsiyet IN ('E', 'K')),
	adres varchar(50) NOT NULL,
	dogum_tarihi date NOT NULL
);

CREATE TABLE doktor (
	tc char(11) PRIMARY KEY,
	isim varchar(50) NOT NULL,
	soyisim varchar(50) NOT NULL,
	cinsiyet char(1) NOT NULL CHECK (cinsiyet IN ('E', 'K')),
	alan varchar(50) NOT NULL,
	unvan varchar(50) NOT NULL
);

CREATE SEQUENCE recete_id_seq
INCREMENT BY 1
START WITH 1;

CREATE TABLE recete (
	recete_id int PRIMARY KEY DEFAULT nextVal('recete_id_seq'),
	hasta_tc char(11) REFERENCES hasta(tc) ON DELETE CASCADE NOT NULL,
	doktor_tc char(11) REFERENCES doktor(tc) ON DELETE CASCADE NOT NULL,
	ilac varchar(50) NOT NULL,
	verilen_tarih date DEFAULT CURRENT_DATE,
	bitis_tarih date NOT NULL
);

CREATE SEQUENCE randevu_id_seq
INCREMENT BY 1
START WITH 1;

CREATE TABLE randevu (
	randevu_id int PRIMARY KEY DEFAULT nextVal('randevu_id_seq'),
	hasta_tc char(11) REFERENCES hasta(tc) ON DELETE CASCADE NOT NULL,
	doktor_tc char(11) REFERENCES doktor(tc) ON DELETE CASCADE NOT NULL,
	tarih timestamp NOT NULL
);

CREATE SEQUENCE muayene_id_seq
INCREMENT BY 1
START WITH 1;

CREATE TABLE muayene (
	muayene_id int DEFAULT nextVal('muayene_id_seq'),
	randevu_id int REFERENCES randevu ON DELETE CASCADE,
	sikayet varchar(50) NOT NULL,
	teshis varchar(50),
	PRIMARY KEY (muayene_id, randevu_id)
);

CREATE FUNCTION muayene_silme_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
	IF EXISTS (
		SELECT *
		FROM randevu
		WHERE randevu_id = OLD.randevu_id
	) THEN
		RAISE EXCEPTION 'Yapılan muayene silinemez.';
		RETURN NULL;
	ELSE
		RETURN OLD;
	END IF;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER muayene_silme_trigger
BEFORE DELETE
ON muayene
FOR EACH ROW EXECUTE PROCEDURE muayene_silme_trigger_fn();

CREATE FUNCTION randevu_cakisma_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
	IF EXISTS (
		SELECT *
		FROM randevu
		WHERE NEW.doktor_tc = doktor_tc AND NEW.tarih BETWEEN tarih - 30 * INTERVAL '1 minute' AND tarih + 30 * INTERVAL '1 minute'
	) THEN
		RAISE EXCEPTION 'Doktorun yarım saat içerisinde başka bir randevusu var.';
		RETURN NULL;
	ELSIF EXISTS (
		SELECT *
		FROM randevu
		WHERE NEW.hasta_tc = hasta_tc AND NEW.tarih BETWEEN tarih - 30 * INTERVAL '1 minute' AND tarih + 30 * INTERVAL '1 minute'
	) THEN
		RAISE EXCEPTION 'Hastanın yarım saat içerisinde başka bir randevusu var.';
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER randevu_cakisma_trigger
BEFORE INSERT
ON randevu
FOR EACH ROW EXECUTE PROCEDURE randevu_cakisma_trigger_fn();

CREATE FUNCTION erken_muayene_trigger_fn()
RETURNS TRIGGER AS $$
DECLARE
	randevuID randevu.randevu_id%TYPE := NEW.randevu_id;
BEGIN
	IF EXISTS (
		SELECT *
		FROM randevu
		WHERE randevuID = randevu_id AND tarih >= CURRENT_TIMESTAMP
	) THEN
		RAISE EXCEPTION 'Tarihi gelmeyen randevu için muayene girişi yapılamaz.';
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER erken_muayene_trigger
BEFORE INSERT
ON muayene
FOR EACH ROW EXECUTE PROCEDURE erken_muayene_trigger_fn();

CREATE FUNCTION doktor_sayi_siniri_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
	IF (
		SELECT COUNT(*)
		FROM doktor
	) = 25 THEN
		RAISE EXCEPTION 'Doktor sayısı 25ten fazla olamaz.';
		RETURN NULL;
	ELSE
		RETURN NEW;
	END IF;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER doktor_sayi_siniri_trigger
BEFORE INSERT
ON doktor
FOR EACH ROW EXECUTE PROCEDURE doktor_sayi_siniri_trigger_fn();

CREATE VIEW tamamlanmis_randevulari_goster AS
SELECT *
FROM randevu NATURAL JOIN muayene;

CREATE TYPE randevu_bilgileri AS (
	doktor_tc char(11),
	isim varchar(50),
	soyisim varchar(50),
	cinsiyet char(1),
	alan varchar(50),
	unvan varchar(50),
	tarih timestamp
);

CREATE FUNCTION hasta_randevulari(hastaTC hasta.tc%TYPE)
RETURNS randevu_bilgileri[] AS $$
DECLARE
	randevular CURSOR FOR (
		SELECT doktor_tc, isim, soyisim, cinsiyet, alan, unvan, tarih
		FROM randevu, doktor
		WHERE hasta_tc = hastaTC AND doktor_tc = tc
	);
	sonuc randevu_bilgileri[];
	i int := 1;
BEGIN
	FOR r IN randevular LOOP
		sonuc[i] = r;
		i := i + 1;
	END LOOP;
	RETURN sonuc;
END;
$$ LANGUAGE 'plpgsql';

CREATE TYPE kullanici AS (
	tc char(11),
	isim varchar(50),
	soyisim varchar(50),
	cinsiyet char(1),
	rol varchar(50)
);

CREATE FUNCTION kullanici_ara(arama kullanici.isim%TYPE)
RETURNS kullanici[] AS $$
DECLARE
	sorgu varchar(50) := REPLACE('%arama%', 'arama', arama);
	kullanicilar CURSOR FOR (
		SELECT *
		FROM (
			(SELECT tc, isim, soyisim, cinsiyet, 'hasta' AS rol FROM hasta)
			UNION
			(SELECT tc, isim, soyisim, cinsiyet, 'doktor' AS rol FROM doktor)
		) AS tablo
		WHERE tc LIKE sorgu OR isim LIKE sorgu OR soyisim LIKE sorgu
	);
	sonuc kullanici[];
	i int := 1;
BEGIN
	FOR k IN kullanicilar LOOP
		sonuc[i] = k;
		i := i + 1;
	END LOOP;
	RETURN sonuc;
END;
$$ LANGUAGE 'plpgsql';

CREATE TYPE doktor_recete AS (
	tc char(11),
	isim varchar(50),
	soyisim varchar(50),
	ilac varchar(50),
	verilen_tarih date,
	bitis_tarih date
);

CREATE FUNCTION hastanin_recetelerini_listele(hastaTC hasta.tc%TYPE)
RETURNS doktor_recete[] AS $$
DECLARE
	receteler CURSOR FOR (
		SELECT tc, isim, soyisim, ilac, verilen_tarih, bitis_tarih
		FROM recete, doktor
		WHERE doktor_tc = tc AND hasta_tc = hastaTC
	);
	sonuc doktor_recete[];
	i int := 1;
BEGIN
	FOR k IN receteler LOOP
		sonuc[i] = k;
		i := i + 1;
	END LOOP;
	RETURN sonuc;
END;
$$ LANGUAGE 'plpgsql';