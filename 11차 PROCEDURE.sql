
CREATE OR REPLACE PROCEDURE PROC_INS_PURCHASE_HISTORY_TB(P_NAME IN VARCHAR2, P_JUMIN_NUMBER IN VARCHAR2, P_PURCHASE_ADDRESS IN VARCHAR2, P_PURCHASE_CNT IN NUMBER, P_PROXY_PURCHASE_NAME IN VARCHAR2, P_PROXY_PURCHASE_JUMIN_NUMBER IN VARCHAR2, P_PAY IN VARCHAR2)
    IS 
        L_YEAR VARCHAR2(10);
        L_TODAY VARCHAR2(10);
        L_AGE NUMBER;
        L_DISABLE_STATUS VARCHAR2(10);
        L_MAX_PURCHASE_CNT NUMBER := 3;
        L_POSSIBLE_PURCHASE_CNT NUMBER;
        L_PROXY_PURCHASE_STATUS VARCHAR2(10) := NULL;
              
        EX_NO_PURCHASE_DAY EXCEPTION;
        EX_NO_PURCHASE_CNT EXCEPTION;
        EX_NO_PURCHASE_POSSIBLE_CNT EXCEPTION; 
        EX_NO_PURCHASE_POSSIBLE_MAX EXCEPTION;
        EX_NO_RESIDENT EXCEPTION;
        EX_NO_PROXY_PURCHASE EXCEPTION;
        
       
        
    BEGIN
        L_YEAR := SUBSTR(P_JUMIN_NUMBER, 2,1);
        SELECT TO_CHAR(SYSDATE, 'D') INTO L_TODAY FROM DUAL;
        
        --마스크 5부제 체크
        IF L_TODAY = '2' AND L_YEAR != '1' AND L_YEAR != '6' THEN
            RAISE EX_NO_PURCHASE_DAY;
            
        ELSIF L_TODAY = '3' AND L_YEAR !='2' AND L_YEAR != '7' THEN
            RAISE EX_NO_PURCHASE_DAY;
            
        ELSIF L_TODAY = '4' AND L_YEAR !='3' AND L_YEAR != '8' THEN
            RAISE EX_NO_PURCHASE_DAY;
            
        ELSIF L_TODAY = '5' AND L_YEAR !='4' AND L_YEAR != '9' THEN
            RAISE EX_NO_PURCHASE_DAY;
            
        ELSIF L_TODAY = '6' AND L_YEAR !='5' AND L_YEAR != '0' THEN
            RAISE EX_NO_PURCHASE_DAY;         
            
        END IF;



        --구매했던 총 마스크 개수 확인 
        FOR X IN(SELECT DISTINCT TOTAL_PURCHASE_CNT 
                    FROM PURCHASE_HISTORY_TB 
                    WHERE JUMIN_NUMBER = P_JUMIN_NUMBER 
                    AND PURCHASE_DATE BETWEEN TRUNC(SYSDATE, 'IW') AND TRUNC(SYSDATE,'IW')+7)
        LOOP

            --이번주에 3장 다 구매한 경우
            IF X.TOTAL_PURCHASE_CNT >= L_MAX_PURCHASE_CNT THEN
                RAISE EX_NO_PURCHASE_CNT;
            
            --처음부터 최대 구매 개수보다 많이 사려는 경우    
            ELSIF L_MAX_PURCHASE_CNT < P_PURCHASE_CNT THEN
                RAISE EX_NO_PURCHASE_POSSIBLE_MAX;
           
            --남은 구매 가능한 개수 보다 많이 구매 하려는 경우     
            ELSIF X.TOTAL_PURCHASE_CNT + P_PURCHASE_CNT > L_MAX_PURCHASE_CNT THEN    
                L_POSSIBLE_PURCHASE_CNT := L_MAX_PURCHASE_CNT - X.TOTAL_PURCHASE_CNT ;
                RAISE EX_NO_PURCHASE_POSSIBLE_CNT;
            END IF;

        END LOOP;
        
        --대리 구매인 경우 
        IF P_PROXY_PURCHASE_NAME IS NOT NULL AND P_PROXY_PURCHASE_JUMIN_NUMBER IS NOT NULL THEN
            
            --만 나이 구하기 
            SELECT FLOOR(MONTHS_BETWEEN(SYSDATE, TO_DATE(BIRTH_YMD,'YYYYMMDD'))/12) INTO L_AGE
            FROM    
            (
                SELECT CASE WHEN SUBSTR(SUBSTR(P_JUMIN_NUMBER,1,6)||SUBSTR(P_JUMIN_NUMBER,8),7,1) IN ('1','2','5','6') THEN '19'
                            WHEN SUBSTR(SUBSTR(P_JUMIN_NUMBER,1,6)||SUBSTR(P_JUMIN_NUMBER,8),7,1) IN ('3','4','7','8') THEN '20'
                            WHEN SUBSTR(SUBSTR(P_JUMIN_NUMBER,1,6)||SUBSTR(P_JUMIN_NUMBER,8),7,1) IN ('9','0') THEN '18' END
                       || SUBSTR(SUBSTR(P_JUMIN_NUMBER,1,6)||SUBSTR(P_JUMIN_NUMBER,8),1,6) BIRTH_YMD
                FROM DUAL
            );
            
            --장애 여부 체크 
            SELECT NVL2(DISABLED_STATUS,'O','X') INTO L_DISABLE_STATUS FROM PERSON_INFO_TB WHERE JUMIN_NUMBER = P_JUMIN_NUMBER;    
            
            --세대주 체크 (10살 이하, 80살 이상, 장애인인 경우 )
            IF L_AGE <= 10 OR L_AGE >=80 OR L_DISABLE_STATUS = 'O' THEN
                FOR X IN (SELECT RESIDENT_NAME, RESIDENT_JUMIN_NUMBER 
                            FROM PERSON_INFO_TB 
                            WHERE JUMIN_NUMBER = P_JUMIN_NUMBER)
                LOOP
                    IF X.RESIDENT_NAME != P_PROXY_PURCHASE_NAME 
                       OR X.RESIDENT_JUMIN_NUMBER != P_PROXY_PURCHASE_JUMIN_NUMBER THEN
                            RAISE EX_NO_RESIDENT;
                    ELSE L_PROXY_PURCHASE_STATUS := 'O';    
                    END IF;
                END LOOP;
            ELSE 
                RAISE EX_NO_PROXY_PURCHASE;
            END IF;
            
        END IF;
        
        
        INSERT INTO PURCHASE_HISTORY_TB (NAME, 
                                      JUMIN_NUMBER, 
                                      ADDRESS, 
                                      PURCHASE_DATE, 
                                      WEEKDAY_PURCHASE_CNT, 
                                      WEEKEND_PURCHASE_CNT, 
                                      PROXY_PURCHASE_STATUS, 
                                      PROXY_PURCHASE_NAME, 
                                      PROXY_PURCHASE_JUMIN_NUMBER, 
                                      PURCHASE_ADDRESS, 
                                      PAY)
        (SELECT NAME, 
                JUMIN_NUMBER, 
                ADDRESS,
                TO_DATE(TO_CHAR(SYSDATE, 'YYYY-MM-DD AM HH:MI:SS'), 'YYYY-MM-DD AM HH:MI:SS') AS PURCHASE_DATE,
                CASE WHEN L_TODAY != 1 AND L_TODAY != 7 THEN P_PURCHASE_CNT
                     ELSE 0
                     END, 
                CASE WHEN L_TODAY = 1 OR L_TODAY = 7 THEN P_PURCHASE_CNT
                     ELSE 0
                     END,
                NVL2(L_PROXY_PURCHASE_STATUS, L_PROXY_PURCHASE_STATUS, NULL),
                DECODE(L_PROXY_PURCHASE_STATUS, 'O', P_PROXY_PURCHASE_NAME, NULL),
                DECODE(L_PROXY_PURCHASE_STATUS, 'O', P_PROXY_PURCHASE_JUMIN_NUMBER, NULL),
                P_PURCHASE_ADDRESS,
                P_PAY
        FROM PERSON_INFO_TB
        WHERE JUMIN_NUMBER = P_JUMIN_NUMBER);
            
        
        UPDATE  PURCHASE_HISTORY_TB A 
        SET (TOTAL_PURCHASE_CNT) 
                = (SELECT WEEKDAY_PURCHASE_CNT + WEEKEND_PURCHASE_CNT
                    FROM
                    (SELECT SUM(WEEKDAY_PURCHASE_CNT) AS WEEKDAY_PURCHASE_CNT, 
                            SUM(WEEKEND_PURCHASE_CNT) AS WEEKEND_PURCHASE_CNT 
                        FROM PURCHASE_HISTORY_TB
                        WHERE PURCHASE_HISTORY_TB.JUMIN_NUMBER = P_JUMIN_NUMBER
                        AND PURCHASE_DATE BETWEEN TRUNC(SYSDATE, 'IW') AND TRUNC(SYSDATE,'IW')+7))
        WHERE A.JUMIN_NUMBER = P_JUMIN_NUMBER
        AND PURCHASE_DATE BETWEEN TRUNC(SYSDATE, 'IW') AND TRUNC(SYSDATE, 'IW')+7;
               
     
       EXCEPTION 
       WHEN EX_NO_PURCHASE_DAY THEN
            DBMS_OUTPUT.PUT_LINE('구매 가능한 날짜가 아닙니다. 5부제 날짜를 확인해주세요.');
       WHEN EX_NO_PURCHASE_CNT THEN
            DBMS_OUTPUT.PUT_LINE('이번주에 이미 마스크를 총 3장 모두 구매 하였습니다. 다음주에 구매해 주세요.' );
       WHEN EX_NO_PURCHASE_POSSIBLE_CNT THEN
            DBMS_OUTPUT.PUT_LINE('마스크 구매 가능 개수는 '||L_POSSIBLE_PURCHASE_CNT||'개 입니다.');
       WHEN EX_NO_PURCHASE_POSSIBLE_MAX THEN
            DBMS_OUTPUT.PUT_LINE('마스크는 '||L_MAX_PURCHASE_CNT||'개 까지 구매 할 수 있습니다.' );
       WHEN EX_NO_PROXY_PURCHASE THEN
            DBMS_OUTPUT.PUT_LINE('대리 구매 대상자는 만 10세 이하 어린이 및 만 80세 이상 노인과 장애인인 경우 입니다.' );
       WHEN EX_NO_RESIDENT THEN
            DBMS_OUTPUT.PUT_LINE('주민등록등본에 등록된 세대주가 아니기 때문에 대리 구매가 불가능 합니다.');
        
        
    END;
