import java.io.*;
import java.security.MessageDigest;
import java.util.*;
import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Mã hoá lại lớp AES bọc ngoài hash bcrypt của lila, để XOAY khoá
 * user.password.bpass.secret mà KHÔNG làm hỏng mật khẩu của ai.
 *
 * Cấu trúc bpass (xem modules/security/src/main/PasswordHasher.scala):
 *   bpass = salt(16) ++ AES/CTS/NoPadding(iv = salt, key = secret)( bcryptRaw(sha512(pw), salt) )
 *   tổng 39 byte, phần mã hoá 23 byte.
 * Khoá chỉ là khoá AES ĐẢO NGƯỢC ĐƯỢC bọc ngoài, không phải thành phần của bcrypt,
 * nên giải bằng khoá cũ rồi mã lại bằng khoá mới cho ra hash tương đương tuyệt đối.
 *
 * stdin : mỗi dòng "<userId>\t<bpass base64>"
 * stdout: mỗi dòng "<userId>\t<bpass base64 mới>"
 */
public class Rotate {

  static SecretKeySpec key(String b64) {
    return new SecretKeySpec(Base64.getDecoder().decode(b64), "AES");
  }

  static byte[] crypt(int mode, SecretKeySpec k, byte[] iv, byte[] data) throws Exception {
    Cipher c = Cipher.getInstance("AES/CTS/NoPadding");
    c.init(mode, k, new IvParameterSpec(iv));
    return c.doFinal(data);
  }

  public static void main(String[] args) throws Exception {
    if (args.length > 0 && args[0].equals("--maxkey")) {
      System.out.println("maxAllowedKeyLength=" + Cipher.getMaxAllowedKeyLength("AES/CTS/NoPadding"));
      return;
    }

    SecretKeySpec oldKey = key(args[0]);
    SecretKeySpec newKey = key(args[1]);

    BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
    StringBuilder out = new StringBuilder();
    int ok = 0, skipped = 0;

    String line;
    while ((line = in.readLine()) != null) {
      line = line.trim();
      if (line.isEmpty()) continue;

      String[] p = line.split("\t");
      if (p.length != 2) { System.err.println("SKIP dòng lạ: " + line); skipped++; continue; }

      byte[] all = Base64.getDecoder().decode(p[1]);
      if (all.length != 39) {
        // lila chỉ chấp nhận đúng 39 byte (PasswordHasher.parse); dài khác = tài khoản
        // không có mật khẩu dùng được, đụng vào chỉ làm hỏng thêm.
        System.err.println("SKIP " + p[0] + " dài " + all.length + " byte (không phải 39)");
        skipped++;
        continue;
      }

      byte[] salt = Arrays.copyOfRange(all, 0, 16);
      byte[] enc = Arrays.copyOfRange(all, 16, 39);

      byte[] plain = crypt(Cipher.DECRYPT_MODE, oldKey, salt, enc);
      byte[] reEnc = crypt(Cipher.ENCRYPT_MODE, newKey, salt, plain);

      // Tự kiểm từng bản ghi: giải lại bằng khoá MỚI phải ra đúng payload bcrypt cũ.
      // Sai một bản ghi là dừng cả mẻ, không ghi ra gì.
      byte[] back = crypt(Cipher.DECRYPT_MODE, newKey, salt, reEnc);
      if (!MessageDigest.isEqual(plain, back))
        throw new IllegalStateException("vòng lặp kiểm tra HỎNG ở " + p[0]);
      if (reEnc.length != 23)
        throw new IllegalStateException("độ dài sau mã hoá lệch ở " + p[0] + ": " + reEnc.length);

      byte[] merged = new byte[39];
      System.arraycopy(salt, 0, merged, 0, 16);
      System.arraycopy(reEnc, 0, merged, 16, 23);

      out.append(p[0]).append('\t').append(Base64.getEncoder().encodeToString(merged)).append('\n');
      ok++;
    }

    System.out.print(out);
    System.err.println("đã xoay=" + ok + " bỏ qua=" + skipped);
  }
}
