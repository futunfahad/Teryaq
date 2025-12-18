from etl.dbETL import normalize_and_load

if __name__ == "__main__":
    file_path = "data/patients.csv"
    normalize_and_load(file_path, "HospitalA")
