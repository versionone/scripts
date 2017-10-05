SELECT T1.ID, T3.Value, T1.PasswordHash FROM [Login] T1
	INNER JOIN [Member_Now] T2 ON T1.ID = T2.ID
	INNER JOIN [String] T3 ON T2.Nickname = T3.ID