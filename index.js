const express = require("express");
const app = express();
const { Pool } = require("pg");
const pug = require("pug");
const bodyParser = require("body-parser");
const fs = require("fs");
require("dotenv").config();

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Listening at port ${PORT}.`));
app.use(bodyParser.urlencoded({ extended: true }));

const pool = new Pool({
	connectionString: process.env.DATABASE_URL,
	ssl: { rejectUnauthorized: false }
});

let views = {};
fs.readdirSync("./views").forEach(view => {
	views[view.split(".pug")[0]] = pug.compileFile(`./views/${view}`);
});

const query = {
	hasta_ekle: "INSERT INTO hasta(tc, isim, soyisim, cinsiyet, adres, dogum_tarihi) VALUES($1, $2, $3, $4, $5, $6)",
	doktor_ekle: "INSERT INTO doktor(tc, isim, soyisim, cinsiyet, alan, unvan) VALUES($1, $2, $3, $4, $5, $6)",
	recete_ekle: "INSERT INTO recete(hasta_tc, doktor_tc, ilac, verilen_tarih, bitis_tarih) VALUES($1, $2, $3, $4, $5)",
	muayene_ekle: "INSERT INTO muayene(randevu_id, sikayet, teshis) VALUES($1, $2, $3)",
	randevu_ekle: "INSERT INTO randevu(hasta_tc, doktor_tc, tarih) VALUES($1, $2, $3)",
	hasta_guncelle: "UPDATE hasta SET isim = $2, soyisim = $3, cinsiyet = $4, adres = $5, dogum_tarihi = $6 WHERE tc = $1",
	doktor_guncelle: "UPDATE doktor SET isim = $2, soyisim = $3, cinsiyet = $4, alan = $5, unvan = $6 WHERE tc = $1",
	recete_guncelle: "UPDATE recete SET hasta_tc = $2, doktor_tc = $3, ilac = $4, verilen_tarih = $5, bitis_tarih = $6 WHERE recete_id = $1",
	muayene_guncelle: "UPDATE muayene SET randevu_id = $2, sikayet = $3, teshis = $4 WHERE muayene_id = $1",
	randevu_guncelle: "UPDATE randevu SET hasta_tc = $2, doktor_tc = $3, tarih = $4 WHERE randevu_id = $1",
	hasta_sil: "DELETE FROM hasta WHERE tc = $1",
	doktor_sil: "DELETE FROM doktor WHERE tc = $1",
	recete_sil: "DELETE FROM recete WHERE recete_id = $1",
	muayene_sil: "DELETE FROM muayene WHERE muayene_id = $1",
	randevu_sil: "DELETE FROM randevu WHERE randevu_id = $1",
	doktor_randevulari: "SELECT tc, isim, soyisim, cinsiyet, adres, dogum_tarihi, tarih FROM randevu, hasta WHERE tc = hasta_tc AND doktor_tc = $1",
	kullanicilari_listele: `
		(SELECT tc, isim, soyisim, cinsiyet, 'hasta' AS rol FROM hasta)
		UNION
		(SELECT tc, isim, soyisim, cinsiyet, 'doktor' AS rol FROM doktor)
	`,
	birden_fazla_hastaya_bakan_doktorlari_listele: `
		SELECT doktor_tc, isim, soyisim, COUNT(*) as hasta_sayisi
		FROM randevu, doktor
		WHERE tarih >= CURRENT_TIMESTAMP AND doktor_tc = tc
		GROUP BY doktor_tc, isim, soyisim
		HAVING COUNT(*) > 1
		ORDER BY hasta_sayisi DESC
	`,
	tamamlanmis_randevulari_goster: "SELECT * FROM tamamlanmis_randevulari_goster",
	hasta_randevulari: "SELECT * FROM UNNEST(hasta_randevulari($1))",
	kullanici_ara: "SELECT * FROM UNNEST(kullanici_ara($1))",
	hastanin_recetelerini_listele: "SELECT * FROM UNNEST(hastanin_recetelerini_listele($1))"
};

app.get("/", (req, res) => {
	res.send(views.layout());	
});

const tables = ["hasta", "doktor", "recete", "muayene", "randevu"];

/*** LİSTELE ***/
tables.forEach(table => {
	app.get(`/${table}_listele`, (req, res) => {
		pool.query(`SELECT * FROM ${table}`, (error, result) => {
			res.send(views[`${table}_listele`]({
				error,
				result: result && result.rows || []
			}));
		})
	});
});

/*** EKLE & GÜNCELLE ***/
["ekle", "guncelle", "sil"].forEach(postfix => {
	tables.forEach(table => {
		app.get(`/${table}_${postfix}`, (req, res) => {
			res.send(views[`${table}_${postfix}`]());
		});

		app.post(`/${table}_${postfix}`, (req, res) => {
			const values = Object.values(req.body).map(i => i === "" ? null : i.trim());
			pool.query(query[`${table}_${postfix}`], values, (error, result) => {
				res.send(views[`${table}_${postfix}`]({
					error,
					result: []
				}));
			});
		});
	});
});

/*** DOKTOR RANDEVULARI ***/
app.get("/doktor_randevulari", (req, res) => {
	res.send(views["doktor_randevulari"]());
});

app.post("/doktor_randevulari", (req, res) => {
	const values = Object.values(req.body).map(i => i === "" ? null : i.trim());
	pool.query(query["doktor_randevulari"], values, (error, result) => {
		res.send(views["doktor_randevulari"]({
			error,
			result: result && result.rows || []
		}));
	});
});

/*** KULLANICILARI LİSTELE ***/
app.get("/kullanicilari_listele", (req, res) => {
	pool.query(query["kullanicilari_listele"], (error, result) => {
		res.send(views["kullanicilari_listele"]({
			error,
			result: result && result.rows || []
		}));
	});
});

/*** BİRDEN FAZLA HASTAYA BAKAN DOKTORLARI LİSTELE ***/
app.get("/birden_fazla_hastaya_bakan_doktorlari_listele", (req, res) => {
	pool.query(query["birden_fazla_hastaya_bakan_doktorlari_listele"], (error, result) => {
		res.send(views["birden_fazla_hastaya_bakan_doktorlari_listele"]({
			error,
			result: result && result.rows || []
		}));
	});
});

/*** TAMAMLANMIŞ RANDEVULARI GÖSTER ***/
app.get("/tamamlanmis_randevulari_goster", (req, res) => {
	pool.query(query["tamamlanmis_randevulari_goster"], (error, result) => {
		res.send(views["tamamlanmis_randevulari_goster"]({
			error,
			result: result && result.rows || []
		}));
	});
});

/*** HASTA RANDEVULARI ***/
app.get("/hasta_randevulari", (req, res) => {
	res.send(views["hasta_randevulari"]());
});

app.post("/hasta_randevulari", (req, res) => {
	const values = Object.values(req.body).map(i => i === "" ? null : i.trim());
	pool.query(query["hasta_randevulari"], values, (error, result) => {
		res.send(views["hasta_randevulari"]({
			error,
			result: result && result.rows || []
		}));
	});
});

/*** KULLANICI ARA ***/
app.get("/kullanici_ara", (req, res) => {
	res.send(views["kullanici_ara"]());
});

app.post("/kullanici_ara", (req, res) => {
	const values = Object.values(req.body).map(i => i === "" ? null : i.trim());
	pool.query(query["kullanici_ara"], values, (error, result) => {
		res.send(views["kullanici_ara"]({
			error,
			result: result && result.rows || []
		}));
	});
});

/*** HASTANIN REÇETELERİNİ LİSTELE ***/
app.get("/hastanin_recetelerini_listele", (req, res) => {
	res.send(views["hastanin_recetelerini_listele"]());
});

app.post("/hastanin_recetelerini_listele", (req, res) => {
	const values = Object.values(req.body).map(i => i === "" ? null : i.trim());
	pool.query(query["hastanin_recetelerini_listele"], values, (error, result) => {
		res.send(views["hastanin_recetelerini_listele"]({
			error,
			result: result && result.rows || []
		}));
	});
});
